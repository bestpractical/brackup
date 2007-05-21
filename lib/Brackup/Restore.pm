package Brackup::Restore;
use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1;
use File::Temp qw(tempfile);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{to}     = delete $opts{to};      # directory we're restoring to
    $self->{prefix} = delete $opts{prefix};  # directory/file filename prefix, or "" for all
    $self->{file}   = delete $opts{file};    # filename we're restoring from

    $self->{_stats_to_run} = [];  # stack (push/pop) of subrefs to reset stat info on

    die "Destination directory doesn't exist" unless $self->{to} && -d $self->{to};
    die "Backup file doesn't exist"           unless $self->{file} && -f $self->{file};
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;
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

sub restore {
    my ($self) = @_;
    my $parser = $self->parser;
    my $meta = $parser->();
    my $driver_class = $meta->{BackupDriver};
    die "No driver specified" unless $driver_class;

    my $driver_meta = _driver_meta($meta);

    eval "use $driver_class; 1;" or die
        "Failed to load driver ($driver_class) to restore from: $@\n";
    my $target = eval {"$driver_class"->new_from_backup_header($driver_meta); };
    if ($@) {
        die "Failed to instantiate target ($driver_class) for restore, perhaps it doesn't support restoring yet?\n\nThe error was: $@";
    }
    $self->{_target} = $target;
    $self->{_meta}   = $meta;

    while (my $it = $parser->()) {
        my $full = $self->{to} . "/" . $it->{Path};
        my $type = $it->{Type} || "f";
        die "Unknown filetype: type=$type, file: $it->{Path}" unless $type =~ /^[ldf]$/;

        # restore default modes from header
        $it->{Mode} ||= $meta->{DefaultFileMode} if $type eq "f";
        $it->{Mode} ||= $meta->{DefaultDirMode}  if $type eq "d";

        $self->_restore_link     ($full, $it) if $type eq "l";
        $self->_restore_directory($full, $it) if $type eq "d";
        $self->_restore_file     ($full, $it) if $type eq "f";
        #warn " * restored $it->{Path} to $full\n";
    }

    $self->_exec_statinfo_updates;

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
    my ($self, $dataref) = @_;

    # find which key we're decrypting it using, else return chunk
    # unmodified in the not-encrypted case
    my $rcpt = $self->{_meta}{"GPG-Recipient"} or
        return $dataref;

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

    my $output_temp = $self->_output_temp_filename;
    my $enc_temp    = $self->_encrypted_temp_filename;

    _write_to_file($enc_temp, $dataref);

    my @list = ("gpg", @Brackup::GPG_ARGS,
                "--use-agent",
                "--batch",
                "--trust-model=always",
                "--output",  $output_temp,
                "--yes", "--quiet",
                "--decrypt", $enc_temp);
    system(@list)
        and die "Failed to decrypt with gpg: $!\n";

    my $ref = _read_file($output_temp);
    return $ref;
}

sub _update_statinfo {
    my ($self, $full, $it) = @_;

    push @{ $self->{_stats_to_run} }, sub {
        if (defined $it->{Mode}) {
            chmod(oct $it->{Mode}, $full) or
                die "Failed to change mode of $full: $!";
        }

        if ($it->{Mtime} || $it->{Atime}) {
            utime($it->{Atime}, $it->{Mtime}, $full) or
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

sub _restore_file {
    my ($self, $full, $it) = @_;

    if (-e $full) {
        # TODO: add --conflict={skip,overwrite} option, defaulting to nothing: which dies
        die "File $full ($it->{Path}) already exists.  Aborting.";
    }

    open (my $fh, ">$full") or die "Failed to open $full for writing";
    my @chunks = grep { $_ } split(/\s+/, $it->{Chunks} || "");
    foreach my $ch (@chunks) {
        my ($offset, $len, $enc_len, $dig) = split(/;/, $ch);
        my $dataref = $self->{_target}->load_chunk($dig) or
            die "Error loading chunk $dig from the restore target\n";

        my $len_chunk = length $$dataref;
        unless ($len_chunk == $enc_len) {
            die "Backup chunk $dig isn't of expected length: got $len_chunk, expecting $enc_len\n";
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
    open (my $fh, $self->{file}) or die "Failed to open metafile: $!";
    return sub {
        my $ret = {};
        my $last;  # scalarref to last item
        my $line;  #
        while (defined ($line = <$fh>)) {
            if ($line =~ /^([\w\-]+):\s*(.+)/) {
                $ret->{$1} = $2;
                $last = \$ret->{$1};
                next;
            }
            if ($line eq "\n") {
                return $ret;
            }
            if ($line =~ /^\s+(.+)/) {
                die "Can't continue line without start" unless $last;
                $$last .= " $1";
                next;
            }
            die "Unexpected line in metafile: $line";
        }
        return undef;
    }
}

sub _write_to_file {
    my ($file, $ref) = @_;
    open (my $fh, ">$file") or die "Failed to open $file for writing: $!\n";
    print $fh $$ref;
    close($fh) or die;
    die unless -s $file == length $$ref;
    return 1;
}

sub _read_file {
    my ($file) = @_;
    open (my $fh, $file) or die "Failed to open $file for reading: $!\n";
    my $data = do { local $/; <$fh>; };
    return \$data;
}

1;

