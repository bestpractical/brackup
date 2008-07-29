# -*-perl-*-

use strict;
use Test::More tests => 12;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

SKIP: {

skip "\$ENV{BRACKUP_TEST_SFTP} not set", 12 unless $ENV{BRACKUP_TEST_SFTP};

############### Backup

my ($digdb_fh, $digdb_fn) = tempfile();
close($digdb_fh);
my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data to backup exists");
my $backup_file = do_backup(
                            with_confsec => sub {
                                my $csec = shift;
                                $csec->add("path",          $root_dir);
                                $csec->add("chunk_size",    "2k");
                                $csec->add("digestdb_file", $digdb_fn);
                            },
                            with_targetsec => sub {
                                my $tsec = shift;
                                $tsec->add("type",          'Sftp');
                                $tsec->add("sftp_host",     $ENV{SFTP_HOST} || 'localhost');
                                $tsec->add("sftp_port",     $ENV{SFTP_PORT}) if $ENV{SFTP_PORT};
                                $tsec->add("sftp_user",     $ENV{SFTP_USER} || '');
                            },
                            );

############### Restore

my $restore_dir = do_restore($backup_file);

ok_dirs_match($restore_dir, $root_dir);

}

# vim:sw=4:et

