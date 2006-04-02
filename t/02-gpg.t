# -*-perl-*-

use strict;
use Test::More tests => 12;

use Brackup::Test;
use FindBin qw($Bin);
use File::Temp qw(tempdir tempfile);

############### Backup

my ($digdb_fh, $digdb_fn) = tempfile();

my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data to backup exists");

my $backup_file = do_backup(sub {
    my $csec = shift;
    $csec->add("path",          $root_dir);
    $csec->add("chunk_size",    "2k");
    $csec->add("digestdb_file", $digdb_fn);
    $csec->add("gpg_recipient",      "2149C469");
});

############### Restore

my $restore_dir = do_restore($backup_file);

ok_dirs_match($restore_dir, $root_dir);

