package Brackup::Backup;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{root}    = delete $opts{root};     # Brackup::Root
    $self->{target}  = delete $opts{target};   # Brackup::Target

    $self->{saved_files} = [];   # list of hashrefs
    
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;

    return $self;
}

# returns 1 on success, or dies with error
sub backup {
    my $self = shift;

    my $root   = $self->{root};
    my $target = $self->{target};

    $root->foreach_file(sub {
	my $file = shift;  # a Brackup::File object
	print ($file->as_string . ":\n");

	$file->foreach_chunk(sub {
	    my $chunk = shift;  # a Brackup::Chunk object
	    print "  " . $chunk->as_string . "\n";
	    unless ($target->has_chunk($chunk)) {
		$target->store_chunk($chunk);
	    }
	});

	$self->add_file($file);
    });

    return 1;
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

