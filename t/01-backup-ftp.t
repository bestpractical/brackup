# -*-perl-*-
#
# Backup test of ftp target - set BRACKUP_TEST_FTP in your environment to use
#
# By default, attempts to do anonymous uploads to localhost, so configure your
# ftp server appropriately, or set FTP_HOST, FTP_USER, and FTP_PASSWORD.
#
# Note that unlike the equivalent Filesystem and Sftp tests, this one does not
# cleanup after itself, since in the default anonymous mode the owner of the
# uploaded files is likely to be different from the user running the test.
#

use strict;
use Test::More tests => 12;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

SKIP: {

skip "\$ENV{BRACKUP_TEST_FTP} not set", 12 unless $ENV{BRACKUP_TEST_FTP};

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
                                $tsec->add("type",          'Ftp');
                                $tsec->add("ftp_host",      $ENV{FTP_HOST} || 'localhost');
                                $tsec->add("ftp_user",      $ENV{FTP_USER} || 'anonymous');
                                $tsec->add("ftp_password",  $ENV{FTP_PASSWORD} || 'user@example.com');
                            },
                            );

############### Restore

$ENV{FTP_PASSWORD} ||= 'user@example.com';

my $restore_dir = do_restore($backup_file);

ok_dirs_match($restore_dir, $root_dir);

}

# vim:sw=4:et

