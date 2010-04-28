# -*-perl-*-

use strict;
use Test::More;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

############### Backup

if (`gpg --version`) {
    plan tests => 13;
} else {
    plan skip_all => 'gpg binary not found, skipping encrypted tests';
}

my $gpg_args = ["--no-default-keyring",
                "--quiet",
                "--keyring=$Bin/data/pubring-test.gpg",
                "--secret-keyring=$Bin/data/secring-test.gpg"];

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
                                $csec->add("gpg_recipient", "2149C469");
                            },
                            with_root => sub {
                                my $root = shift;
                                $root->{gpg_args} = $gpg_args;
                            },
                            );

############### Restore

my $restore_dir = do {
    local @Brackup::GPG_ARGS = @$gpg_args;
    do_restore($backup_file);
};

ok_dirs_match($restore_dir, $root_dir);

