package Brackup::Dict::SQLite;
use strict;
use warnings;
use DBI;
use DBD::SQLite;

sub new {
    my ($class, $table, $file) = @_;
    my $self = bless {
        table => $table,
        file  => $file,
        data  => {},
    }, $class;

    my $dbh = $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$file","","", { RaiseError => 1, PrintError => 0 }) or
        die "Failed to connect to SQLite filesystem digest cache database at $file: " . DBI->errstr;

    eval {
        $dbh->do("CREATE TABLE $table (key TEXT PRIMARY KEY, value TEXT)");
    };
    die "Error: $@" if $@ && $@ !~ /table \w+ already exists/;

    # SQLite sucks at doing anything quickly (likes hundred thousand
    # selects back-to-back), so we just suck the whole damn thing into
    # a perl hash.  cute, huh?  then it doesn't have to
    # open/read/seek/seek/seek/read/close for each select later.
    my $sth = $self->{dbh}->prepare("SELECT key, value FROM $self->{table}");
    $sth->execute;
    while (my ($k, $v) = $sth->fetchrow_array) {
        $self->{data}{$k} = $v;
    }

    return $self;
}

sub get {
    my ($self, $key) = @_;
    return $self->{data}{$key};
}

sub set {
    my ($self, $key, $val) = @_;
    $self->{dbh}->do("REPLACE INTO $self->{table} VALUES (?,?)", undef, $key, $val);
    $self->{data}{$key} = $val;
    return 1;
}

sub backing_file {
    my $self = shift;
    return $self->{file};
}

sub wipe {
    die "not implemented";
}

1;

