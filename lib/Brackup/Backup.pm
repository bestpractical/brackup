package Brackup::Backup;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{root}    = delete $opts{root};     # Brackup::Root
    $self->{target}  = delete $opts{target};   # Brackup::Target
    $self->{dryrun}  = delete $opts{dryrun};   # bool

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

    # store the files
    $root->foreach_file(sub {
        my ($file, $progress) = @_;  # a Brackup::File and Brackup::Progress

        print STDERR "  ", $file->path, "\n";

        $file->foreach_chunk(sub {
            my $chunk = shift;  # a Brackup::Chunk object

            if ($target->has_chunk($chunk)) {
                return;
            }

            $chunk->will_need_data;

            unless ($self->{dryrun}) {
                $target->store_chunk($chunk) or die "Chunk storage failed.\n";
            }
            $stats->note_stored_chunk($chunk);

            # DEBUG: verify it got written correctly
            if ($ENV{BRACKUP_PARANOID}) {
                my $saved_ref = $target->load_chunk($chunk->backup_digest);
                my $saved_len = length $$saved_ref;
                unless ($saved_len == $chunk->backup_length) {
                    warn "Saved length of $saved_len doesn't match our length of " . $chunk->backup_length . "\n";
                    die;
                }
            }

            $chunk->forget_chunkref;
        });

        $self->add_file($file);
    });

    # write the metafile
    open (my $metafh, ">$backup_file") or die "Failed to open $backup_file for writing: $!\n";
    print $metafh $self->backup_header;
    $self->foreach_saved_file(sub {
        my $file = shift;
        print $metafh $file->as_rfc822;
    });
    close $metafh or die;

    my $contents;

    # store the metafile, encrypted, on the target
    if (my $rcpt = $self->{root}->gpg_rcpt) {
        my $encfile .= ".enc";
        system($self->{root}->gpg_path, $self->{root}->gpg_args,
               "--trust-model=always",
               "--recipient", $rcpt, "--encrypt", "--output=$encfile", "--yes", $backup_file)
            and die "Failed to run gpg while encryping metafile: $!\n";
        $contents = _contents_of($encfile);
        unlink $encfile;
    } else {
        $contents = _contents_of($backup_file);
    }

    # store it on the target
    my $name = $self->{root}->publicname . "-" . $self->backup_time;
    $target->store_backup_meta($name, $contents);

    return $stats;
}

sub _contents_of {
    my $file = shift;
    open (my $fh, $file) or die "Failed to read contents of $file: $!\n";
    return do { local $/; <$fh>; };
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
    if (my $rcpt = $self->{root}->gpg_rcpt) {
        $ret .= "GPG-Recipient: $rcpt\n";
    }
    $ret .= "\n";
    return $ret;
}

sub add_file {
    my ($self, $file) = @_;
    push @{ $self->{saved_files} }, $file;
}

sub foreach_saved_file {
    my ($self, $cb) = @_;
    foreach my $file (@{ $self->{saved_files} }) {
        $cb->($file);
    }
}

1;

