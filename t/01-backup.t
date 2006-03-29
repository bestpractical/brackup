# -*-perl-*-

use strict;
use Test::More tests => 1;

use FindBin qw($Bin);
use File::Temp qw(tempdir tempfile);

use Brackup::Root;
use Brackup::Config;
use Brackup::Backup;
use Brackup::Restore;
use Brackup::DigestDatabase;
use Brackup::Target;
use Brackup::Target::Filesystem;
use Brackup::File;
use Brackup::Chunk;

my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data to backup exists");

my ($digdb_fh, $digdb_fn) = tempfile();

my $conf = Brackup::ConfigSection->new("SOURCE:test_root");
$conf->add("path",       $root_dir);
$conf->add("chunk_size", "2k");
$conf->add("digestdb_file", $digdb_fn);

my $root = Brackup::Root->new($conf);
ok($root, "have a source root");

chdir($root_dir) or die;
my $pre_ls = `ls -lR .`;

my $backup_dir = tempdir( CLEANUP => 1 );
ok_dir_empty($backup_dir);

my $restore_dir = tempdir( CLEANUP => 1 );
ok_dir_empty($restore_dir);

$conf = Brackup::ConfigSection->new("TARGET:test_restore");
$conf->add("type" => "Filesystem");
$conf->add("path" => $backup_dir);
my $target = Brackup::Target::Filesystem->new($conf);
ok($target, "have a target");

my $backup = Brackup::Backup->new(
                                  root    => $root,
                                  target  => $target,
                                  );
ok($backup, "have a backup object");

my ($meta_fh, $meta_filename) = tempfile();

ok(eval { $backup->backup($meta_filename) }, "backup succeeded");
ok(-s $meta_filename, "backup file has size");
system("cat", $meta_filename);

my $restore = Brackup::Restore->new(
                                    to     => $restore_dir,
                                    prefix => "",  # backup everything
                                    file   => $meta_filename,
                                    );
ok($restore, "have restore object");
ok(eval { $restore->restore; }, "did the restore: $@");
chdir($restore_dir) or die;
my $post_ls = `ls -lR .`;
is($post_ls, $pre_ls, "restore matches original");


sub ok_dir_empty {
    my $dir = shift;
    unless (-d $dir) { ok(0, "not a dir"); return; }
    opendir(my $dh, $dir) or die "failed to opendir: $!";
    is_deeply([ sort readdir($dh) ], ['.', '..'], "dir is empty: $dir");
}
