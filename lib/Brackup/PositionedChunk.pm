package Brackup::PositionedChunk;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);

use fields (
            'file',     # the Brackup::File object
            'offset',   # offset within said file
            'length',   # length of data
            '_raw_digest',
            '_raw_chunkref',
            );

sub new {
    my ($class, %opts) = @_;
    my $self = ref $class ? $class : fields::new($class);

    $self->{file}   = delete $opts{'file'};    # Brackup::File object
    $self->{offset} = delete $opts{'offset'};
    $self->{length} = delete $opts{'length'};

    croak("Unknown options: " . join(', ', keys %opts)) if %opts;
    croak("offset not numeric") unless $self->{offset} =~ /^\d+$/;
    croak("length not numeric") unless $self->{length} =~ /^\d+$/;
    return $self;
}

sub as_string {
    my $self = shift;
    return $self->{file}->as_string . "{off=$self->{offset},len=$self->{length}}";
}

# the original length, pre-encryption
sub length {
    my $self = shift;
    return $self->{length};
}

sub offset {
    my $self = shift;
    return $self->{offset};
}

sub file {
    my $self = shift;
    return $self->{file};
}

sub root {
    my $self = shift;
    return $self->file->root;
}

sub raw_digest {
    my $self = shift;
    return $self->{_raw_digest} if $self->{_raw_digest};

    my $cache = $self->root->digest_cache;
    my $key   = $self->cachekey;
    my $dig;

    if ($dig = $cache->get($key)) {
        return $self->{_raw_digest} = $dig;
    }

    my $rchunk = $self->raw_chunkref;
    $dig = "sha1:" . sha1_hex($$rchunk);

    $cache->set($key => $dig);

    return $self->{_raw_digest} = $dig;
}

sub raw_chunkref {
    my $self = shift;
    return $self->{_raw_chunkref} if $self->{_raw_chunkref};

    my $data;
    my $fullpath = $self->{file}->fullpath;
    open(my $fh, $fullpath) or die "Failed to open $fullpath: $!\n";
    binmode($fh);
    seek($fh, $self->{offset}, 0) or die "Couldn't seek: $!\n";
    my $rv = read($fh, $data, $self->{length})
        or die "Failed to read: $!\n";
    unless ($rv == $self->{length}) {
        Carp::confess("Read $rv bytes, not $self->{length}");
    }

    return $self->{_raw_chunkref} = \$data;
}

# useful string for targets to key on.  of one of the forms:
#    "<digest>;to=<enc_to>"
#    "<digest>;raw"
#    "<digest>;gz"   (future)
sub inventory_key {
    my $self = shift;
    my $key = $self->raw_digest;
    if (my $rcpt = $self->root->gpg_rcpt) {
        $key .= ";to=$rcpt";
    } else {
        $key .= ";raw";
    }
    return $key;
}

sub forget_chunkref {
    my $self = shift;
    delete $self->{_raw_chunkref};
}

sub cachekey {
    my $self = shift;
    return $self->{file}->cachekey . ";o=$self->{offset};l=$self->{length}";
}

1;
