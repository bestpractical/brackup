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
    my $dig = $chunk->backup_digest;   # "sha1-sdfsdf" format scalar
    warn "FIXME (has chunk?  dig=$dig)";
    return 0; 
}

sub store_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;
    my $blen = $chunk->backup_length;
    my $len = $chunk->length;
    
    warn "NOT STORING CHUNK, dig=$dig, len=$len, blen=$blen\n";
}

1;

