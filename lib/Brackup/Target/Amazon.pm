package Brackup::Target::Amazon;
use strict;
use warnings;
use base 'Brackup::Target';
use Net::Amazon::S3;
use DBD::SQLite;

sub new {
    my ($class, $confsec) = @_;
    my $self = bless {}, $class;

    if (my $cache_file = $confsec->value("exist_cache")) {
	$self->{dbh} = DBI->connect("dbi:SQLite:dbname=$cache_file","","", { RaiseError => 1, PrintError => 0 }) or
	    die "Failed to connect to SQLite filesystem digest cache database at $cache_file: " . DBI->errstr;

	eval {
	    $self->{dbh}->do("CREATE TABLE amazon_key_exists (key TEXT PRIMARY KEY, value TEXT)");
	};
	die "Error: $@" if $@ && $@ !~ /table brackupcache already exists/;
    }

    $self->{access_key_id} = $confsec->value("aws_access_key_id")   or die "No 'aws_access_key_id'";
    my $sec = $confsec->value("aws_secret_access_key")              or die "No 'aws_secret_access_key'";

    my $s3 = $self->{s3} = Net::Amazon::S3->new({
	aws_access_key_id     => $self->{access_key_id},
	aws_secret_access_key => $sec,
    });

    my $buckets = $s3->buckets or die "Failed to get bucket list";

    $self->{chunk_bucket} = $self->{access_key_id} . "-chunks";
    unless (grep { $_->{bucket} eq $self->{chunk_bucket} } @{ $buckets->{buckets} }) {
	$s3->add_bucket({ bucket => $self->{chunk_bucket} })
	    or die "Chunk bucket creation failed\n";
    }

    $self->{backup_bucket} = $self->{access_key_id} . "-backups";
    unless (grep { $_->{bucket} eq $self->{backup_bucket} } @{ $buckets->{buckets} }) {
	$s3->add_bucket({ bucket => $self->{backup_bucket} })
	    or die "Backup bucket creation failed\n";
    }

    return $self;
}

sub has_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;   # "sha1:sdfsdf" format scalar

    if (my $dbh = $self->{dbh}) {
	my $ans = $dbh->selectrow_array("SELECT COUNT(*) FROM amazon_key_exists WHERE key=?", undef, $dig);
	warn "amazon database for $dig is = $ans\n";
	return $ans;
    }

    my $res = eval { $self->{s3}->head_key({ bucket => $self->{chunk_bucket}, key => $dig }); };
    return 0 if $@ && $@ =~ /key not found/;

    return $res->{content_type} eq "x-danga/brackup-chunk";
}

sub store_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;
    my $blen = $chunk->backup_length;
    my $len = $chunk->length;

    my $rv = $self->{s3}->add_key({
	bucket        => $self->{chunk_bucket},
	key           => $dig,
	value         => ${ $chunk->chunkref },
	content_type  => 'x-danga/brackup-chunk',
    });
    warn "store chunk = $rv\n";

    use Data::Dumper;
    warn Dumper($rv);

    # until add_key's return value is good, let's just double-check it made it before we update our cache
    if ($self->has_chunk($chunk)) {
	if (my $dbh = $self->{dbh}) {
	    $dbh->do("INSERT INTO amazon_key_exists VALUES (?,1)", undef, $dig);
	}
	return 1;
    }
    return 0;
}

sub store_backup_meta {
    my ($self, $name, $file) = @_;

    my $rv = $self->{s3}->add_key({
	bucket        => $self->{backup_bucket},
	key           => $name,
	value         => $file,
	content_type  => 'x-danga/brackup-meta',
    });

    warn "backup meta = $rv\n";
    return $rv;
}

1;

