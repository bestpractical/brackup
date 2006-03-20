package Brackup::Chunk;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);

#gpg --recipient 5E1B3EC5 --encrypt --output=file.enc file.orig
#gpg --output file.dec --decrypt file.enc

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

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

sub root {
    my $self = shift;
    return $self->{file}->root;
}

sub length {
    my $self = shift;
    return $self->{length} if $self->{length};
    my $dataref = $self->chunkref;
    $self->_learn_lengthdigest($dataref);
    return $self->{length};
}

sub _learn_lengthdigest {
    my ($self, $dataref) = @_;
    $self->{length} = length $$dataref;
    $self->{digest} = "sha1-" . sha1_hex($$dataref);
    1;
}

sub digest {
    my $self = shift;
    return $self->{digest} if $self->{digest};

    my $root = $self->root;
    my $cache = $root->cache;
    if ($cache->chunk_
}

1;

