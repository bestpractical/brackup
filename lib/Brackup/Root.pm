package Brackup::Root;
use strict;
use warnings;
use Carp qw(croak);
use File::Find;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{name}       = delete $opts{name};
    $self->{dir}        = delete $opts{dir};
    $self->{chunk_size} = delete $opts{chunk_size};
    $self->{cache}      = delete $opts{cache};  # a Brackup::DigestCache object
    $self->{ignore}     = [];
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;

    die "No backup-root name provided." unless $self->{name};
    die "Backup-root name must be only a-z, A-Z, 0-9, and _." unless $self->{name} =~ /^\w+/;
    die "No backup-root directory provided." unless $self->{dir};
    die "Backup-root directory isn't a directory: $self->{dir}" unless -d $self->{dir};

    return $self;
}

sub cache {
    my $self = shift;
    return $self->{cache};
}

sub chunk_size {
    my $self = shift;
    return $self->{chunk_size} || (64 * 2**20);  # default to 64MB
}

sub name {
    return $_[0]{name};
}

sub ignore {
    my ($self, $pattern) = @_;
    push @{ $self->{ignore} }, $pattern;
}

sub path {
    return $_[0]{dir};
}

sub foreach_file {
    my ($self, $cb) = @_;

    chdir $self->{dir} or die "Failed to chdir to $self->{dir}";

    find({
	no_chdir => 1,
	wanted => sub {
	    my (@stat) = stat(_);
	    my $path = $_;
	    $path =~ s!^\./!!;
	    foreach my $pattern (@{ $self->{ignore} }) {
		return if $path =~ /$pattern/;
	    }
	    my $file = Brackup::File->new(root => $self, path => $path);
	    $cb->($file);
	},
    }, ".");
}

sub as_string {
    my $self = shift;
    return $self->{name} . "($self->{dir})";
}

1;

