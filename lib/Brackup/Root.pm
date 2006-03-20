package Brackup::Root;
use strict;
use warnings;
use Carp qw(croak);
use File::Find;

sub new {
    my ($class, $conf, $cache) = @_;
    my $self = bless {}, $class;

    my $name = $conf->name;
    $name =~ s!^SOURCE:!! or die;

    $self->{name}       = $name;
    $self->{dir}        = $conf->path_value('path');
    $self->{gpg_rcpt}   = $conf->value('gpg_recipient');
    $self->{chunk_size} = $conf->byte_value('chunk_size'),
    $self->{cache}      = $cache;   # a Brackup::DigestCache object
    $self->{ignore}     = [];

    die "No backup-root name provided." unless $self->{name};
    die "Backup-root name must be only a-z, A-Z, 0-9, and _." unless $self->{name} =~ /^\w+/;

    return $self;
}

sub gpg_rcpt {
    my $self = shift;
    return $self->{gpg_rcpt};
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

