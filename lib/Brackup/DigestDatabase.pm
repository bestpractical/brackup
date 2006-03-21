package Brackup::DigestDatabase;
use strict;
use warnings;
use DBI;
use DBD::SQLite;

sub new {
    my ($class, $file) = @_;
    my $self = bless {}, $class;
    my $dbh = $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$file","","", { RaiseError => 1, PrintError => 0 }) or
	die "Failed to connect to SQLite filesystem digest cache database at $file: " . DBI->errstr;

    eval {
	$dbh->do("CREATE TABLE brackupcache (key TEXT PRIMARY KEY, value TEXT)");
    };
    die "Error: $@" if $@ && $@ !~ /table brackupcache already exists/;

    return $self;
}

sub get {
    my ($self, $key) = @_;
    my $val = $self->{dbh}->selectrow_array("SELECT value FROM brackupcache WHERE key=?",
					    undef, $key);
    return $val;
}

sub set {
    my ($self, $key, $val) = @_;
    $self->{dbh}->do("REPLACE INTO brackupcache VALUES (?,?)", undef, $key, $val);
    return 1;
}

sub wipe {
    die "not implemented";
}

1;

