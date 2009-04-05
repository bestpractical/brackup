# -*-perl-*-

use strict;
use Test::More tests => 10;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

SKIP: {

skip "\$ENV{BRACKUP_TEST_FTP} not set", 10 unless $ENV{BRACKUP_TEST_FTP};

############### Backup

my ($digdb_fh, $digdb_fn) = tempfile();
close($digdb_fh);
my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data to backup exists");
my ($backup_file, $backup, $target) = do_backup(
                            with_confsec => sub {
                                my $csec = shift;
                                $csec->add("path",          $root_dir);
                                $csec->add("chunk_size",    "2k");
                                $csec->add("digestdb_file", $digdb_fn);
                            },
                            with_targetsec => sub {
                                my $tsec = shift;
                                $tsec->add("type",          'Ftp');
                                $tsec->add("ftp_host",      $ENV{FTP_HOST} || 'localhost');
                                $tsec->add("ftp_user",      $ENV{FTP_USER} || 'anonymous');
                                $tsec->add("ftp_password",  $ENV{FTP_PASSWORD} || 'user@example.com');
                            },
                            );

############### Add an orphan chunk

my $orphan_chunks_count = int(rand 10) + 1;
for (1..$orphan_chunks_count) {
    my $chunk = Brackup::StoredChunk->new;
    $chunk->{_chunkref} = \ "foobar $_";
    $target->store_chunk($chunk);
}

############### Do garbage collection

my $removed_count = eval { $target->gc };
is($@, '', "gc successful");
is($removed_count, $orphan_chunks_count, "all orphan chunks removed");

}

# vim:sw=4:et

