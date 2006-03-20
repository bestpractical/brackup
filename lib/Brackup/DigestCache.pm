package Brackup::DigestCache;
use strict;
use warnings;
use DBI;
use DBD::SQLite;

sub new {
    my ($class, $file) = @_;
    my $self = bless {}, $class;
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$file","","") or
	die "Failed to connect to SQLite filesystem digest cache database at $file: " . DBI->errstr;
    return $self;
}

sub full_digest {
    my ($self, $key) = @_;
    warn "GET KEY ($key)\n";
    return undef;
}

sub set_full_digest {
    my ($self, $key, $val) = @_;
    warn "SET KEY ($key) = $val\n";
}

sub wipe {
    die "not implemented";
}

1;

