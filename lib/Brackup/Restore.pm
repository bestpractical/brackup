package Brackup::Restore;
use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1;
use Brackup::Util qw(tempfile slurp valid_params);
use POSIX qw(mkfifo);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{to}      = delete $opts{to};      # directory we're restoring to
    $self->{prefix}  = delete $opts{prefix};  # directory/file filename prefix, or "" for all
    $self->{file}    = delete $opts{file};    # filename we're restoring from
    $self->{verbose} = delete $opts{verbose};

    $self->{prefix} =~ s/\/$// if $self->{prefix};

    $self->{_stats_to_run} = [];  # stack (push/pop) of subrefs to reset stat info on

    die "Destination directory doesn't exist" unless $self->{to} && -d $self->{to};
    die "Backup file doesn't exist"           unless $self->{file} && -f $self->{file};
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;

    $self->decrypt_file_if_needed;

    return $self;
}

# returns a hashref of { "foo" => "bar" } from { ..., "Driver-foo" => "bar" }
sub _driver_meta {
    my $src = shift;
    my $ret = {};
    foreach my $k (keys %$src) {
        next unless $k =~ /^Driver-(.+)/;
        $ret->{$1} = $src->{$k};
    }
    return $ret;
}

sub decrypt_file_if_needed {
    my $self = shift;
    my $meta = slurp($self->{file});
    if ($meta =~ /[\x00-\x08]/) { # silly is-binary heuristic
        my $new_file = $self->_decrypt_data(\$meta,
                                            want_tempfile => 1,
                                            no_batch => 1,
                                            );
        warn "Decrypted metafile $self->{file} to $new_file; using that to restore from...\n";
        $self->{file} = $new_file;
        scalar <STDIN>;
    }
}

sub restore {
    my ($self) = @_;
    my $parser = $self->parser;
    my $meta = $parser->readline;
    my $driver_class = $meta->{BackupDriver};
    die "No driver specified" unless $driver_class;

    my $driver_meta = _driver_meta($meta);

    eval "use $driver_class; 1;" or die
        "Failed to load driver ($driver_class) to restore from: $@\n";
    my $target = eval {"$driver_class"->new_from_backup_header($driver_meta); };
    if ($@) {
        die "Failed to instantiate target ($driver_class) for restore. Perhaps it doesn't support restoring yet?\n\nThe error was: $@";
    }
    $self->{_target} = $target;
    $self->{_meta}   = $meta;

    while (my $it = $parser->readline) {
        my $type = $it->{Type} || "f";
        die "Unknown filetype: type=$type, file: $it->{Path}" unless $type =~ /^[ldfp]$/;

        if ($self->{prefix}) {
            next unless $it->{Path} =~ m/^\Q$self->{prefix}\E(?:\/|$)/;
            # if non-dir and $it->{Path} eq $self->{prefix}, strip all but last component
            if ($type ne 'd' && $it->{Path} =~ m/^\Q$self->{prefix}\E\/?$/) {
                if (my ($leading_prefix) = ($self->{prefix} =~ m/^(.*\/)[^\/]+\/?$/)) {
                    $it->{Path} =~ s/^\Q$leading_prefix\E//;
                }
            }
            else {
                $it->{Path} =~ s/^\Q$self->{prefix}\E\/?//;
            }
        }

        my $full = $self->{to} . "/" . $it->{Path};

        # restore default modes from header
        $it->{Mode} ||= $meta->{DefaultFileMode} if $type eq "f";
        $it->{Mode} ||= $meta->{DefaultDirMode}  if $type eq "d";

        warn " * restoring $it->{Path} to $full\n" if $self->{verbose};
        $self->_restore_link     ($full, $it) if $type eq "l";
        $self->_restore_directory($full, $it) if $type eq "d";
        $self->_restore_fifo     ($full, $it) if $type eq "p";
        $self->_restore_file     ($full, $it) if $type eq "f";
    }

    warn " * fixing stat info\n" if $self->{verbose};
    $self->_exec_statinfo_updates;
    warn " * done\n" if $self->{verbose};
    return 1;
}

sub _output_temp_filename {
    my $self = shift;
    return $self->{_output_temp_filename} ||= ( (tempfile())[1] || die );
}

sub _encrypted_temp_filename {
    my $self = shift;
    return $self->{_encrypted_temp_filename} ||= ( (tempfile())[1] || die );
}

sub _decrypt_data {
    my $self = shift;
    my $dataref = shift;
    my %opts = valid_params(['no_batch', 'want_tempfile'], @_);

    # find which key we're decrypting it using, else return chunk
    # unmodified in the not-encrypted case
    if ($self->{_meta}) {
        my $rcpt = $self->{_meta}{"GPG-Recipient"} or
            return $dataref;
    }

    unless ($ENV{'GPG_AGENT_INFO'} ||
            @Brackup::GPG_ARGS ||
            $self->{warned_about_gpg_agent}++)
    {
        my $err = q{#
                        # WARNING: trying to restore encrypted files,
                        # but $ENV{'GPG_AGENT_INFO'} not present.
                        # Are you running gpg-agent?
                        #
                    };
        $err =~ s/^\s+//gm;
        warn $err;
    }

    my $output_temp = $opts{want_tempfile} ?
        (tempfile())[1]
        : $self->_output_temp_filename;
    my $enc_temp    = $self->_encrypted_temp_filename;

    _write_to_file($enc_temp, $dataref);

    my @list = ("gpg", @Brackup::GPG_ARGS,
                "--use-agent",
                !$opts{no_batch} ? ("--batch") : (),
                "--trust-model=always",
                "--output",  $output_temp,
                "--yes", "--quiet",
                "--decrypt", $enc_temp);
    system(@list)
        and die "Failed to decrypt with gpg: $!\n";

    return $output_temp if $opts{want_tempfile};
    my $data = Brackup::Util::slurp($output_temp);
    return \$data;
}

sub _update_statinfo {
    my ($self, $full, $it) = @_;

    push @{ $self->{_stats_to_run} }, sub {
        if (defined $it->{Mode}) {
            chmod(oct $it->{Mode}, $full) or
                die "Failed to change mode of $full: $!";
        }

        if ($it->{Mtime} || $it->{Atime}) {
            utime($it->{Atime} || $it->{Mtime},
                  $it->{Mtime} || $it->{Atime},
                  $full) or
                die "Failed to change utime of $full: $!";
        }
    };
}

sub _exec_statinfo_updates {
    my $self = shift;

    # change the modes/times in backwards order, going from deep
    # files/directories to shallow ones.  (so we can reliably change
    # all the directory mtimes without kernel doing it for us when we
    # modify files deeper)
    while (my $sb = pop @{ $self->{_stats_to_run} }) {
        $sb->();
    }
}

sub _restore_directory {
    my ($self, $full, $it) = @_;

    unless (-d $full) {
        mkdir $full or    # FIXME: permissions on directory
            die "Failed to make directory: $full ($it->{Path})";
    }

    $self->_update_statinfo($full, $it);
}

sub _restore_link {
    my ($self, $full, $it) = @_;

    if (-e $full) {
        # TODO: add --conflict={skip,overwrite} option, defaulting to nothing: which dies
        die "Link $full ($it->{Path}) already exists.  Aborting.";
    }
    symlink $it->{Link}, $full
        or die "Failed to link";
}

sub _restore_fifo {
    my ($self, $full, $it) = @_;

    if (-e $full) {
        die "Named pipe/fifo $full ($it->{Path}) already exists.  Aborting.";
    }

    mkfifo($full, $it->{Mode}) or die "mkfifo failed: $!";

    $self->_update_statinfo($full, $it);
}

sub _restore_file {
    my ($self, $full, $it) = @_;

    if (-e $full && -s $full) {
        # TODO: add --conflict={skip,overwrite} option, defaulting to nothing: which dies
        die "File $full ($it->{Path}) already exists.  Aborting.";
    }

    open (my $fh, ">$full") or die "Failed to open $full for writing";
    binmode($fh);
    my @chunks = grep { $_ } split(/\s+/, $it->{Chunks} || "");
    foreach my $ch (@chunks) {
        my ($offset, $len, $enc_len, $dig) = split(/;/, $ch);
        my $dataref = $self->{_target}->load_chunk($dig) or
            die "Error loading chunk $dig from the restore target\n";

        my $len_chunk = length $$dataref;

        # using just a range of the file
        # TODO: inefficient!  we don't want to download the chunk from the
        # target multiple times.  better to cache it locally, or at least
        # only fetch a region from the target (but that's still kinda inefficient
        # and pushes complexity into the Target interface)
        if ($enc_len =~ /^(\d+)-(\d+)$/) {
            my ($from, $to) = ($1, $2);
            # file range.  gotta be at least as big as bigger number
            unless ($len_chunk >= $to) {
                die "Backup chunk $dig isn't at least as big as range: got $len_chunk, needing $to\n";
            }
            my $region = substr($$dataref, $from, $to-$from);
            $dataref = \$region;
        } else {
            # using the whole chunk, so make sure fetched size matches
            # expected size
            unless ($len_chunk == $enc_len) {
                die "Backup chunk $dig isn't of expected length: got $len_chunk, expecting $enc_len\n";
            }
        }

        my $decrypted_ref = $self->_decrypt_data($dataref);
        print $fh $$decrypted_ref;
    }
    close($fh) or die "Close failed";

    if (my $good_dig = $it->{Digest}) {
        die "not capable of verifying digests of from anything but sha1"
            unless $good_dig =~ /^sha1:(.+)/;
        $good_dig = $1;

        open (my $readfh, $full) or die "Couldn't reopen file for verification";
        binmode($readfh);
        my $sha1 = Digest::SHA1->new;
        $sha1->addfile($readfh);
        my $actual_dig = $sha1->hexdigest;

        # TODO: support --onerror={continue,prompt}, etc, but for now we just die
        unless ($actual_dig eq $good_dig || $full =~ m!\.brackup-digest\.db\b!) {
            die "Digest of restored file ($full) doesn't match";
        }
    }

    $self->_update_statinfo($full, $it);
}

# returns iterator subref which returns hashrefs or undef on EOF
sub parser {
    my $self = shift;
    return Brackup::Metafile->open($self->{file});
}

sub _write_to_file {
    my ($file, $ref) = @_;
    open (my $fh, ">$file") or die "Failed to open $file for writing: $!\n";
    print $fh $$ref;
    close($fh) or die;
    die "Restored file is not of the correct size" unless -s $file == length $$ref;
    return 1;
}

sub DESTROY {
    my $self = shift;
    unlink(grep { $_ } ($self->{_output_temp_filename},
                        $self->{_encrypted_temp_filename}));
}

1;

