# support module for helping test brackup
package Brackup::Test;
require Exporter;
use strict;
use vars qw(@ISA @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(do_backup do_restore ok_dirs_match);

use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir tempfile);
use File::Find;
use File::stat ();
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

sub do_backup {
    my $initer = shift;
    my $conf = Brackup::ConfigSection->new("SOURCE:test_root");
    $initer->($conf) if $initer;

    my $root = Brackup::Root->new($conf);
    ok($root, "have a source root");

    my $backup_dir = tempdir( CLEANUP => 1 );
    ok_dir_empty($backup_dir);

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
    ok(-e $meta_filename, "metafile exists");

    ok(eval { $backup->backup($meta_filename) }, "backup succeeded");
    ok(-s $meta_filename, "backup file has size");
    return $meta_filename;
}

sub do_restore {
    my $backup_file = shift;
    my $restore_dir = tempdir( CLEANUP => 1 );
    ok_dir_empty($restore_dir);

    my $restore = Brackup::Restore->new(
                                        to     => $restore_dir,
                                        prefix => "",  # backup everything
                                        file   => $backup_file,
                                        );
    ok($restore, "have restore object");
    ok(eval { $restore->restore; }, "did the restore: $@");
    return $restore_dir;
}

sub ok_dirs_match {
    my ($after, $before) = @_;

    my $pre_ls  = dir_structure($before);
    my $post_ls = dir_structure($after);

    if ($has_diff) {
        use Data::Dumper;
        my $pre_dump = Dumper($pre_ls);
        my $post_dump = Dumper($post_ls);
        my $diff = Text::Diff::diff(\$pre_dump, \$post_dump);
        is($diff, "", "dirs match");
    } else {
        is_deeply($post_ls, $pre_ls, "dirs match");
    }
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
    chdir($dir) or die "Failed to chdir to $dir";

    find({
        no_chdir => 1,
        wanted => sub {
            my $path = $_;
            my $st = File::stat::lstat($path);

            my $meta = {};
            $meta->{size} = $st->size;
            $meta->{is_file} = 1 if -f $path;
            $meta->{is_link} = 1 if -l $path;
            if ($meta->{is_link}) {
                $meta->{link} = readlink $path;
            } else {
                # we ignore these for links, since Linux doesn't let us restore anyway,
                # as Linux as no lutimes(2) syscall, as of Linux 2.6.16 at least
                $meta->{atime} = $st->atime;
                $meta->{mtime} = $st->mtime;
                $meta->{mode}  = sprintf('%#o', $st->mode & 0777);
            }
            $files{$path} = $meta;
        },
    }, ".");

    chdir($cwd) or die "Failed to chdir back to $cwd";
    return \%files;
}


1;
