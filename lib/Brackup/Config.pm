package Brackup::Config;

use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub add_section {
    my ($self, $sec) = @_;
    $self->{$sec->name} = $sec;
}

sub load {
    my ($class, $file) = @_;
    my $self = bless {}, $class;

    open (my $fh, $file) or do {
        if (write_dummy_config($file)) {
            die "Your config file needs tweaking.  I put a commented-out template at: $file\n";
        } else {
            die "No config file at: $file\n";
        }
    };
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

    unless ($sec) {
        die "Your config file needs tweaking.  There's a starting template at: $file\n";
    }

    return $self;
}

sub default_config_file_name {
    my ($class) = @_;
    
    if ($ENV{HOME}) {
        # Default for UNIX folk
        return "$ENV{HOME}/.brackup.conf";
    }
    elsif ($ENV{APPDATA}) {
        # For Windows users
        return "$ENV{APPDATA}/brackup.conf";
    }
    else {
        # Fall back on the current directory
        return "brackup.conf";
    }

}

sub write_dummy_config {
    my $file = shift;
    open (my $fh, ">$file") or return;
    print $fh <<ENDCONF;
# This is an example config

#[TARGET:raidbackups]
#type = Filesystem
#path = /raid/backup/brackup

#[TARGET:amazon]
#type = Amazon
#aws_access_key_id  = XXXXXXXXXX
#aws_secret_access_key =  XXXXXXXXXXXX

#[SOURCE:proj]
#path = /raid/bradfitz/proj/
#chunk_size = 5m
#gpg_recipient = 5E1B3EC5

#[SOURCE:bradhome]
#path = /raid/bradfitz/
#chunk_size = 64MB
#ignore = ^\.thumbnails/
#ignore = ^\.kde/share/thumbnails/
#ignore = ^\.ee/minis/
#ignore = ^build/
#ignore = ^(gqview|nautilus)/thumbnails/

ENDCONF
}

sub load_root {
    my ($self, $name, $cache) = @_;
    my $conf = $self->{"SOURCE:$name"} or
        die "Unknown source '$name'\n";

    my $root = Brackup::Root->new($conf, $cache);

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

    # abort if the user had any configuration we didn't understand
    if (my @keys = $conf->unused_config) {
        die "Aborting, unknown configuration keys in SOURCE:$name: @keys\n";
    }

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
        _name      => $name,
        _accessed  => {},  # key => 1
    }, $class;
}

sub name {
    my $self = shift;
    return $self->{_name};
}

sub add {
    my ($self, $key, $val) = @_;
    push @{ $self->{$key} ||= [] }, $val;
}

sub unused_config {
    my $self = shift;
    return sort grep { $_ ne "_name" && $_ ne "_accessed" && ! $self->{_accessed}{$_} } keys %$self;
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
    $self->{_accessed}{$key} = 1;
    my $vals = $self->{$key};
    return undef unless $vals;
    die "Configuration section '$self->{_name}' has multiple values of key '$key' where only one is expected.\n"
        if @$vals > 1;
    return $vals->[0];
}

sub values {
    my ($self, $key) = @_;
    $self->{_accessed}{$key} = 1;
    my $vals = $self->{$key};
    return () unless $vals;
    return @$vals;
}

1;

