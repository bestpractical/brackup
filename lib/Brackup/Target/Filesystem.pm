package Brackup::Target::Filesystem;
use strict;
use warnings;
use base 'Brackup::Target';

sub new {
    my ($class, $confsec) = @_;
    my $self = bless {}, $class;
    $self->{path} = $confsec->path_value("path");
    return $self;
}

sub has_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->digest;   # "sha1-sdfsdf" format scalar
    warn "FIXME (has chunk)";
    return 0; 
}

1;

