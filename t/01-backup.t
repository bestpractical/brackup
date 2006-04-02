# -*-perl-*-

use strict;
use Test::More tests => 12;

use FindBin qw($Bin);
use File::Temp qw(tempdir tempfile);
use File::Find;
use Cwd;

use Brackup::Root;
use Brackup::Config;
use Brackup::Backup;
use Brackup::Restore;
use Brackup::DigestDatabase;
use Brackup::Target;
use Brackup::Target::Filesystem;
use Brackup::File;
use Brackup::Chunk;

my $has_diff = eval "use Text::Diff; 1;";

my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data to backup exists");

my ($digdb_fh, $digdb_fn) = tempfile();

my $conf = Brackup::ConfigSection->new("SOURCE:test_root");
$conf->add("path",       $root_dir);
$conf->add("chunk_size", "2k");
$conf->add("digestdb_file", $digdb_fn);

my $root = Brackup::Root->new($conf);
ok($root, "have a source root");

my $pre_ls = dir_structure($root_dir);

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

my $post_ls = dir_structure($restore_dir);

if ($has_diff) {
    use Data::Dumper;
    my $pre_dump = Dumper($pre_ls);
    my $post_dump = Dumper($post_ls);
    my $diff = Text::Diff::diff(\$pre_dump, \$post_dump);
    is($diff, "", "restore matches original");
} else {
    is_deeply($post_ls, $pre_ls, "backup matches restore");
}


sub ok_dir_empty {
    my $dir = shift;
    unless (-d $dir) { ok(0, "not a dir"); return; }
    opendir(my $dh, $dir) or die "failed to opendir: $!";
    is_deeply([ sort readdir($dh) ], ['.', '..'], "dir is empty: $dir");
}

# given a directory, returns a hashref of its contentn
sub dir_structure {
    my $dir = shift;
    my %files;  # "filename" -> {metadata => ...}
    my $cwd = getcwd;
    chdir $dir or die "Failed to chdir to $dir";

    find({
        no_chdir => 1,
        wanted => sub {
            my (@stat) = stat(_);
            my $path = $_;
            my $meta = {};
            $meta->{size} = -s $path;
            $meta->{is_file} = 1 if -f $path;
            $meta->{is_link} = 1 if -l $path;
            if ($meta->{is_link}) {
                $meta->{link} = readlink $path;
            }
            $meta->{atime} = $stat[8];
            $meta->{mtime} = $stat[9];
            $meta->{mode}  = sprintf('%#o', $stat[2] & 0777);
            $files{$path} = $meta;
        },
    }, ".");

    chdir $cwd or die "Failed to chdir back to $cwd";
    return \%files;
}
