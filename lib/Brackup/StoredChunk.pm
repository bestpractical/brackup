package Brackup::StoredChunk;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);

# fields:
#   pchunk - always
#   backlength - memoized
#   backdigest - memoized
#   _chunkref  - memoized

sub new {
    my ($class, $pchunk) = @_;
    my $self = bless {}, $class;
    $self->{pchunk} = $pchunk;
    return $self;
}

# create the 'lite' or 'handle' version of a storedchunk.  can't get to
# the chunkref from this, but callers aren't won't.  and we'll DIE if they
# try to access the chunkref.
sub new_from_inventory {
    my ($class, $pchunk, $dig, $len) = @_;
    return bless {
        pchunk     => $pchunk,
        backdigest => $dig,
        backlength => $len,
    }, $class;
}

sub file {
    my $self = shift;
    return $self->{pchunk}->file;
}

sub root {
    my $self = shift;
    return $self->file->root;
}

# returns true if encrypted, false otherwise
sub encrypted {
    my $self = shift;
    return $self->root->gpg_rcpt ? 1 : 0;
}

sub compressed {
    my $self = shift;
    # TODO/FUTURE: support compressed chunks (for non-encrypted
    # content; gpg already compresses)
    return 0;
}

# the original length, pre-encryption
sub length {
    my $self = shift;
    return $self->{pchunk}->length;
}

# the length, either encrypted or not
sub backup_length {
    my $self = shift;
    return $self->{backlength} if defined $self->{backlength};
    $self->_populate_lengthdigest;
    return $self->{backlength};
}

# the digest, either encrypted or not
sub backup_digest {
    my $self = shift;
    return $self->{backdigest} if $self->{backdigest};
    $self->_populate_lengthdigest;
    return $self->{backdigest};
}

sub _populate_lengthdigest {
    my $self = shift;
    my $dataref = $self->chunkref;
    $self->{backlength} = CORE::length($$dataref);
    $self->{backdigest} = "sha1:" . sha1_hex($$dataref);
    return 1;
}

sub chunkref {
    my $self = shift;
    return $self->{_chunkref} if $self->{_chunkref};

    # caller/consistency check:
    Carp::confess("Can't access chunkref on lite StoredChunk instance (handle only)")
        if $self->{backlength} || $self->{backdigest};

    # non-encrypting case
    unless ($self->encrypted) {
        return $self->{_chunkref} = $self->{pchunk}->raw_chunkref;
    }

    # encrypting case.
    my $enc = $self->root->encrypt($self->{pchunk}->raw_chunkref);
    return $self->{_chunkref} = \$enc;
}

# set scalar/scalarref of encryptd chunkref
sub set_encrypted_chunkref {
    my ($self, $arg) = @_;
    die "ASSERT: not enc"       unless $self->encrypted;
    die "ASSERT: already set?" if $self->{backlength} || $self->{backdigest};

    return $self->{_chunkref} = ref $arg ? $arg : \$arg;
}

# lose the chunkref data
sub forget_chunkref {
    my $self = shift;
    delete $self->{_chunkref};
}

# to the format used by the metafile
sub to_meta {
    my $self = shift;
    my @parts = ($self->{pchunk}->offset,
                 $self->{pchunk}->length,
                 $self->backup_length,
                 $self->backup_digest,
                 );

    # if the inventory database is lost, it should be possible to
    # recover the inventory database from the *.brackup files.
    # if a file only has on chunk, the digest(raw) -> digest(enc)
    # can be inferred from the file's digest, then the stored
    # chunk's digest.  but if we have multiple chunks, we need
    # to store each chunk's raw digest as well in the chunk
    # list.  we could do this all the time, but considering
    # most files are small, we want to save space in the *.brackup
    # meta file and only do it when necessary.
    if ($self->encrypted && $self->file->chunks > 1) {
        push @parts, $self->{pchunk}->raw_digest;
    }

    return join(";", @parts);
}

1;
