package Brackup::Restore;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{to}     = delete $opts{to};      # directory we're restoring to
    $self->{prefix} = delete $opts{prefix};  # directory/file filename prefix, or "" for all
    $self->{file}   = delete $opts{file};    # filename we're restoring from

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

    # subrefs to run in reverse order later
    my @mode_time_updates;

    while (my $it = $parser->()) {
        my $full = $self->{to} . "/" . $it->{Path};
        my $type = $it->{Type} || "f";

        # restore directories
        if ($type eq "d") {
            unless (-d $full) {
                mkdir $full or    # FIXME: permissions on directory
                    die "Failed to make directory: $full ($it->{Path})";
            }
        }

        if ($type eq "l") {
            if (-e $full) {
                # FIXME: add --conflict={skip,overwrite} option, defaulting to nothing: which dies
                die "Link $full ($it->{Path}) already exists.  Aborting.";
            }
            symlink $it->{Link}, $full
                or die "Failed to link";

            #next; # don't fall through to mode/mtime/atime setting
        }

        if ($type eq "f") {
            if (-e $full) {
                # FIXME: add --conflict={skip,overwrite} option, defaulting to nothing: which dies
                die "File $full ($it->{Path}) already exists.  Aborting.";
            }

            open (my $fh, ">$full") or die "Failed to open $full for writing";
            my @chunks = grep { $_ } split(/\s+/, $it->{Chunks});
            foreach my $ch (@chunks) {
                my ($offset, $len, $enc_len, $dig) = split(/;/, $ch);
                print "  dig = [$dig]\n";
                my $dataref = $target->load_chunk($dig) or
                    die "Error loading chunk $dig from the restore target\n";
                unless (length $$dataref == $enc_len) {
                    die "Backup chunk $dig isn't of expected length\n";
                }
                # TODO: decrypt if encrypted
                print $fh $$dataref;
            }
            close($fh);
            if ($it->{Digest}) {
                # verify digest matches
            }
        }

        # note to do this later, after we're done with directory
        push @mode_time_updates, sub {
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

    # change the modes/times in backwards order, going from deep
    # files/directories to shallow ones.  (so we can reliably change
    # all the directory mtimes without kernel doing it for us when we
    # modify files deeper)
    while (my $sb = pop @mode_time_updates) {
        $sb->();
    }

    return 1;
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


1;

