
package Brackup::TargetBackupStatInfo;

use strict;
use warnings;

sub new {
    my ($class, $target, $fn, %opts) = shift;

    my $self = {
        target => $target,
        filename => $fn,
        time => $opts{time},
        size => $opts{size},
    };

    return bless $self, $class;
}

sub target {
    return $_[0]->{target};
}

sub filename {
    return $_[0]->{filename};
}

sub time {
    return $_[0]->{time};
}

sub size {
    return $_[0]->{size};
}


1;

