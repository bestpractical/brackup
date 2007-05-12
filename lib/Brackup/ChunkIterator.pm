package Brackup::ChunkIterator;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, @files) = @_;
    return bless {
        filelist => \@files,
        chunkmag => [],
    }, $class;
}

# returns either PositionedChunks, or, in cases of files
# without contents (like directories/symlinks), returns
# File objects... returns undef on end of files/chunks.
sub next {
    my $self = shift;

    # magazine already loaded?  fire.
    my $next = shift @{ $self->{chunkmag} };
    return $next if $next;

    # else reload...
    my $file = shift @{ $self->{filelist} } or
        return undef;

    ($next, @{$self->{chunkmag}}) = $file->chunks;
    return $next if $next;
    return $file;
}

1;
