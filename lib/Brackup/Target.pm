package Brackup::Target;

use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    croak("Unknown options: " . join(', ', keys %opts)) if %opts;
}

# returns bool
sub has_chunk {
    my ($self, $chunk) = @_;
    die "ERROR: has_chunk not implemented in sub-class $self";
}

# returns true on success, or returns false or dies otherwise.
sub store_chunk {
    my ($self, $chunk) = @_;
    die "ERROR: store_chunk not implemented in sub-class $self";
}

sub store_backup_meta {
    my ($self, $name, $file) = @_;
    die "ERROR: store_backup_meta not implemented in sub-class $self";
}

1;

