package Brackup::GPGProcess;
use strict;
use warnings;
use Brackup::Util qw(tempfile);
use POSIX qw(_exit);

sub new {
    my ($class, $pchunk) = @_;

    my ($destfh, $destfn) = tempfile();

    my $no_fork = 0;  # if true (perhaps on Windows?), then don't fork... do all inline.

    my $pid = $no_fork ? 0 : fork;
    if (!defined $pid) {
        die "Failed to fork: $!";
    }

    # caller (parent)
    if ($pid) {
        return bless {
            destfn    => $destfn,
            pid       => $pid,
            running   => 1,
        }, $class;
    }

    # child:  encrypt and exit(0)...
    my $enc = $pchunk->root->encrypt($pchunk->raw_chunkref);
    my $enc_len = length($enc);

    binmode($destfh);
    print $destfh $enc
        or die "failed to print: $!";
    close $destfh
        or die "failed to close: $!";

    my $wrote_size = -s $destfn;
    unless (defined $wrote_size && $wrote_size == $enc_len) {
        unless (-e $destfn) {
            # if the file's gone, that likely means the parent process
            # already terminated and unlinked our temp file, in
            # which case we should just exit (with error code), rather
            # than spewing error messages to stderr.
            POSIX::_exit(1);
        }
        $wrote_size = "<undef>" unless defined $wrote_size;
        die "size not right (expected $enc_len; got $wrote_size)";
    }

    if ($no_fork) {
        return bless {
            destfn => $destfn,
            pid    => 0,
        }, $class;
    }

    # Note: we have to do this, to avoid some END block, somewhere,
    # from cleaning up something or doing something.  probably tempfiles
    # being destroyed in File::Temp.
    POSIX::_exit(0);
}

sub pid { $_[0]{pid} }

sub running { $_[0]{running} }
sub note_stopped { $_[0]{running} = 0; }

sub chunkref {
    my ($self) = @_;
    die "Still running!" if $self->{running};

    open(my $fh, $self->{destfn})
        or die "Failed to open gpg temp file $self->{destfn}: $!";
    binmode($fh);
    my $data = do { local $/; <$fh>; };
    die "No data in file" unless length $data;
    close($fh);
    unlink($self->{destfn}) or die "couldn't delete destfn";

    # unlink
    return \$data;
}

sub size_on_disk {
    my $self = shift;
    return -s $self->{destfn};
}

1;

