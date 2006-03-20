package Brackup::Config;

use strict;
use warnings;
use Carp qw(croak);

sub load {
    my ($class, $file) = @_;
    my $self = bless {}, $class;

    open (my $fh, $file) or die "No config file at: $file\n";
    my $sec = undef;
    while (my $line = <$fh>) {
	$line =~ s/^\#.*//;   # kill comments starting at beginning of line
	$line =~ s/\s\#.*//;   # kill comments with whitespace before the # (motivation: let # be in regexps)
	$line =~ s/^\s+//;
	$line =~ s/\s$//;
	next unless $line ne "";

	if ($line =~ /^\[(.+)\]$/) {
	    my $name = $1;
	    $sec  = Brackup::ConfigSection->new($name);
	    die "Duplicate config section '$name'" if $self->{$name};
	    $self->{$name} = $sec;
	} elsif ($line =~ /^(\w+)\s*=\s*(.+)/) {
	    die "Declaration of '$1' outside of a section." unless $sec;
	    $sec->add($1, $2);
	} else {
	    die "Bogus config line: $line";
	}
    }

    return $self;
}

sub load_root {
    my ($self, $name, $cache) = @_;
    my $conf = $self->{"SOURCE:$name"} or
	die "Unknown source '$name'\n";

    my $root = Brackup::Root->new(
				  name       => $name,
				  dir        => $conf->value('path'),
				  chunk_size => $conf->byte_value('chunk_size'),
				  cache      => $cache,
				  );

    # iterate over config's ignore, and add those
    foreach my $pat ($conf->values("ignore")) {
	$root->ignore($pat);
    }

    # common things to ignore
    $root->ignore(qr!~$!);
    $root->ignore(qr!^\.thumbnails/!);
    $root->ignore(qr!^\.kde/share/thumbnails/!);
    $root->ignore(qr!^\.ee/minis/!);
    $root->ignore(qr!^\.(gqview|nautilus)/thumbnails/!);
    return $root;
}

sub load_target {
    my ($self, $name) = @_;
    my $conf = $self->{"TARGET:$name"} or
	die "Unknown target '$name'\n";

    my $type = $conf->value("type") or
	die "Target '$name' has no 'type'";
    die "Invalid characters in $name's 'type'"
	unless $type =~ /^\w+$/;

    my $class = "Brackup::Target::$type";
    eval "use $class; 1;" or die
	"Failed to load ${name}'s driver: $@\n";
    return "$class"->new($conf);
}

package Brackup::ConfigSection;
use strict;
use warnings;

sub new {
    my ($class, $name) = @_;
    return bless {
	_name => $name,
    }, $class;
}

sub add {
    my ($self, $key, $val) = @_;
    push @{ $self->{$key} ||= [] }, $val;
}

sub path_value {
    my ($self, $key) = @_;
    my $val = $self->value($key) || "";
    die "Path '$key' of '$val' isn't a valid directory\n"
	unless $val && -d $val;
    return $val;
}

sub byte_value {
    my ($self, $key) = @_;
    my $val = $self->value($key);
    return 0                unless $val;
    return $1               if $val =~ /^(\d+)b?$/i;
    return $1 * 1024        if $val =~ /^(\d+)kb?$/i;
    return $1 * 1024 * 1024 if $val =~ /^(\d+)mb?$/i;
    die "Unrecognized size format: '$val'\n";
}

sub value {
    my ($self, $key) = @_;
    my $vals = $self->{$key};
    return undef unless $vals;
    die "Configuration section '$self->{_name}' has multiple values of key '$key' where only one is expected.\n"
	if @$vals > 1;
    return $vals->[0];
}

sub values {
    my ($self, $key) = @_;
    my $vals = $self->{$key};
    return () unless $vals;
    return @$vals;
}

1;

