package Brackup::Backup;
use strict;
use warnings;
use Carp qw(croak);
use Brackup::ChunkIterator;
use Brackup::CompositeChunk;
use Brackup::GPGProcManager;
use Brackup::GPGProcess;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{root}    = delete $opts{root};     # Brackup::Root
    $self->{target}  = delete $opts{target};   # Brackup::Target
    $self->{dryrun}  = delete $opts{dryrun};   # bool
    $self->{verbose} = delete $opts{verbose};  # bool

    $self->{modecounts} = {}; # type -> mode(octal) -> count

    $self->{saved_files} = [];   # list of Brackup::File objects backed up

    croak("Unknown options: " . join(', ', keys %opts)) if %opts;

    return $self;
}

# returns true (a Brackup::BackupStats object) on success, or dies with error
sub backup {
    my ($self, $backup_file) = @_;

    my $root   = $self->{root};
    my $target = $self->{target};

    my $stats  = Brackup::BackupStats->new;

    my $gpg_rcpt = $self->{root}->gpg_rcpt;

    my $n_kb         = 0.0; # num:  kb of all files in root
    my $n_files      = 0;   # int:  # of files in root
    my $n_kb_done    = 0.0; # num:  kb of files already done with (uploaded or skipped)

    # if we're pre-calculating the amount of data we'll
    # actually need to upload, store it here.
    my $n_kb_up      = 0.0;
    my $n_kb_up_need = 0.0; # by default, not calculated/used.

    my $n_files_done = 0;   # int
    my @files;         # Brackup::File objs

    $self->debug("Discovering files in ", $root->path, "...\n");
    $root->foreach_file(sub {
        my ($file) = @_;  # a Brackup::File
        push @files, $file;
        $n_files++;
        $n_kb += $file->size / 1024;
    });

    $self->debug("Number of files: $n_files\n");

    # calc needed chunks
    if ($ENV{CALC_NEEDED}) {
        my $fn = 0;
        foreach my $f (@files) {
            $fn++;
            if ($fn % 100 == 0) { warn "$fn / $n_files ...\n"; }
            foreach my $pc ($f->chunks) {
                if ($target->stored_chunk_from_inventory($pc)) {
                    $pc->forget_chunkref;
                    next;
                }
                $n_kb_up_need += $pc->length / 1024;
                $pc->forget_chunkref;
            }
        }
        warn "kb need to upload = $n_kb_up_need\n";
    }


    my $chunk_iterator = Brackup::ChunkIterator->new(@files);

    my $gpg_iter;
    my $gpg_pm;   # gpg ProcessManager
    if ($gpg_rcpt) {
        ($chunk_iterator, $gpg_iter) = $chunk_iterator->mux_into(2);
        $gpg_pm = Brackup::GPGProcManager->new($gpg_iter, $target);
    }

    my $cur_file; # current (last seen) file
    my @stored_chunks;
    my $file_has_shown_status = 0;

    my $end_file = sub {
        return unless $cur_file;
        $self->add_file($cur_file, [ @stored_chunks ]);
        $n_files_done++;
        $n_kb_done += $cur_file->size / 1024;
        $cur_file = undef;
    };
    my $show_status = sub {
        # use either size of files in normal case, or if we pre-calculated
        # the size-to-upload (by looking in inventory, then we'll show the
        # more accurate percentage)
        my $percdone = 100 * ($n_kb_up_need ?
                              ($n_kb_up / $n_kb_up_need) :
                              ($n_kb_done / $n_kb));
        my $mb_remain = ($n_kb_up_need ?
                         ($n_kb_up_need - $n_kb_up) :
                         ($n_kb - $n_kb_done)) / 1024;

        $self->debug(sprintf("* %-60s %d/%d (%0.02f%%; remain: %0.01f MB)",
                             $cur_file->path, $n_files_done, $n_files, $percdone,
                             $mb_remain));
    };
    my $start_file = sub {
        $end_file->();
        $cur_file = shift;
        @stored_chunks = ();
        $show_status->() if $cur_file->is_dir;
        if ($gpg_iter) {
            # catch our gpg iterator up.  we want it to be ahead of us,
            # nothing iteresting is behind us.
            $gpg_iter->next while $gpg_iter->behind_by > 1;
        }
        $file_has_shown_status = 0;
    };

    my $merge_under = $root->merge_files_under;
    my $comp_chunk  = undef;
    
    # records are either Brackup::File (for symlinks, directories, etc), or
    # PositionedChunks, in which case the file can asked of the chunk
    while (my $rec = $chunk_iterator->next) {
        if ($rec->isa("Brackup::File")) {
            $start_file->($rec);
            next;
        }
        my $pchunk = $rec;
        if ($pchunk->file != $cur_file) {
            $start_file->($pchunk->file);
        }

        # have we already stored this chunk before?  (iterative backup)
        my $schunk;
        if ($schunk = $target->stored_chunk_from_inventory($pchunk)) {
            $pchunk->forget_chunkref;
            push @stored_chunks, $schunk;
            next;
        }

        # weird case... have we stored this same pchunk digest in the
        # current comp_chunk we're building?  these aren't caught by
        # the above inventory check, because chunks in a composite
        # chunk aren't added to the inventory until after the the composite
        # chunk has fully grown (because it's not until it's fully grown
        # that we know the handle for it, its digest)
        if ($comp_chunk && ($schunk = $comp_chunk->stored_chunk_from_dup_internal_raw($pchunk))) {
            $pchunk->forget_chunkref;
            push @stored_chunks, $schunk;
            next;
        }

        $show_status->() unless $file_has_shown_status++;
        $self->debug("  * storing chunk: ", $pchunk->as_string, "\n");

        unless ($self->{dryrun}) {
            $schunk = Brackup::StoredChunk->new($pchunk);

            # encrypt it
            if ($gpg_rcpt) {
                $schunk->set_encrypted_chunkref($gpg_pm->enc_chunkref_of($pchunk));
            }

            # see if we should pack it into a bigger blob
            my $chunk_size = $schunk->backup_length;
            if ($merge_under && $chunk_size < $merge_under) {
                if ($comp_chunk && ! $comp_chunk->can_fit($chunk_size)) {
                    $self->debug("Finalizing composite chunk $comp_chunk...");
                    $comp_chunk->finalize;
                    $comp_chunk = undef;
                }
                $comp_chunk ||= Brackup::CompositeChunk->new($root, $target);
                $comp_chunk->append_little_chunk($schunk);
            } else {
                # store it regularly, as its own chunk on the target
                $target->store_chunk($schunk)
                    or die "Chunk storage failed.\n";
                $target->add_to_inventory($pchunk => $schunk);
            }

            # if only this worked... (LWP protocol handler seems to
            # get confused by its syscalls getting interrupted?)
            #local $SIG{CHLD} = sub {
            #    print "some child finished!\n";
            #    $gpg_pm->start_some_processes;
            #};


            $n_kb_up += $pchunk->length / 1024;
            push @stored_chunks, $schunk;
        }

        #$stats->note_stored_chunk($schunk);

        # DEBUG: verify it got written correctly
        if ($ENV{BRACKUP_PARANOID}) {
            die "FIX UP TO NEW API";
            #my $saved_ref = $target->load_chunk($handle);
            #my $saved_len = length $$saved_ref;
            #unless ($saved_len == $chunk->backup_length) {
            #    warn "Saved length of $saved_len doesn't match our length of " . $chunk->backup_length . "\n";
            #    die;
            #}
        }

        $pchunk->forget_chunkref;
        $schunk->forget_chunkref if $schunk;
    }
    $end_file->();
    $comp_chunk->finalize if $comp_chunk;

    unless ($self->{dryrun}) {
        # write the metafile
        $self->debug("Writing metafile ($backup_file)");
        open (my $metafh, ">$backup_file") or die "Failed to open $backup_file for writing: $!\n";
        print $metafh $self->backup_header;
        $self->foreach_saved_file(sub {
            my ($file, $schunk_list) = @_;
            print $metafh $file->as_rfc822($schunk_list, $self);  # arrayref of StoredChunks
        });
        close $metafh or die;

        my $contents;

        # store the metafile, encrypted, on the target
        if ($gpg_rcpt) {
            my $encfile = $backup_file . ".enc";
            system($self->{root}->gpg_path, $self->{root}->gpg_args,
                   "--trust-model=always",
                   "--recipient", $gpg_rcpt, "--encrypt", "--output=$encfile", "--yes", $backup_file)
                and die "Failed to run gpg while encryping metafile: $!\n";
            $contents = _contents_of($encfile);
            unlink $encfile;
        } else {
            $contents = _contents_of($backup_file);
        }

        # store it on the target
        $self->debug("Storing metafile to " . ref($target));
        my $name = $self->{root}->publicname . "-" . $self->backup_time;
        $target->store_backup_meta($name, $contents);
    }

    return $stats;
}

sub _contents_of {
    my $file = shift;
    open (my $fh, $file) or die "Failed to read contents of $file: $!\n";
    return do { local $/; <$fh>; };
}

sub default_file_mode {
    my $self = shift;
    return $self->{_def_file_mode} ||= $self->_default_mode('f');
}

sub default_directory_mode {
    my $self = shift;
    return $self->{_def_dir_mode} ||= $self->_default_mode('d');
}

sub _default_mode {
    my ($self, $type) = @_;
    my $map = $self->{modecounts}{$type} || {};
    return (sort { $map->{$b} <=> $map->{$a} } keys %$map)[0];
}

sub backup_time {
    my $self = shift;
    return $self->{backup_time} ||= time();
}

sub backup_header {
    my $self = shift;
    my $ret = "";
    my $now = $self->backup_time;
    $ret .= "BackupTime: " . $now . " (" . localtime($now) . ")\n";
    $ret .= "BackupDriver: " . ref($self->{target}) . "\n";
    if (my $fields = $self->{target}->backup_header) {
        foreach my $k (keys %$fields) {
            die "Bogus header field from driver" unless $k =~ /^\w+$/;
            my $val = $fields->{$k};
            die "Bogus header value from driver" if $val =~ /[\r\n]/;
            $ret .= "Driver-$k: $val\n";
        }
    }
    $ret .= "RootName: " . $self->{root}->name . "\n";
    $ret .= "RootPath: " . $self->{root}->path . "\n";
    $ret .= "DefaultFileMode: " . $self->default_file_mode . "\n";
    $ret .= "DefaultDirMode: " . $self->default_directory_mode . "\n";
    if (my $rcpt = $self->{root}->gpg_rcpt) {
        $ret .= "GPG-Recipient: $rcpt\n";
    }
    $ret .= "\n";
    return $ret;
}

sub add_file {
    my ($self, $file, $handlelist) = @_;
    $self->{modecounts}{$file->type}{$file->mode}++;
    push @{ $self->{saved_files} }, [ $file, $handlelist ];
}

sub foreach_saved_file {
    my ($self, $cb) = @_;
    foreach my $rec (@{ $self->{saved_files} }) {
        $cb->(@$rec);  # Brackup::File, arrayref of Brackup::StoredChunk
    }
}

sub debug {
    my ($self, @m) = @_;
    return unless $self->{verbose};
    my $line = join("", @m);
    chomp $line;
    print $line, "\n";
}

1;

