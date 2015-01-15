# -*-perl-*-

use strict;
use Test::More;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

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
                                $csec->add("ignore",        "(^|/)\.svn/");
                            },
                            );


############### Monkey-patch Restore _update_statinfo and _restore_link to record restored files

my @restored = ();
{ 
    no warnings 'redefine';
    my $update_statinfo = \&Brackup::Restore::_update_statinfo;
    *Brackup::Restore::_update_statinfo = sub {
        my ($self, $full, $it) = @_;
        $update_statinfo->(@_);
        push @restored, $it->{Path};
    };
    my $restore_link = \&Brackup::Restore::_restore_link;
    *Brackup::Restore::_restore_link = sub {
        my ($self, $full, $it) = @_;
        if ($restore_link->(@_)) {
            push @restored, $it->{Path};
        }
    };
}

############### Restore

# Full restore
my $restore_dir = do_restore($backup_file);
ok_dirs_match($restore_dir, $root_dir);

# Restore again, same restore_dir - should die without --conflict flag
ok(unlink("$restore_dir/000-dup1.txt"), 'removed 000-dup1.txt for --conflict undef test');
do_restore($backup_file, restore_dir => $restore_dir, restore_should_die => 1);

# Restore again, same restore_dir - should NOT die with --conflict skip
@restored = ();
ok(unlink("$restore_dir/000-dup2.txt"), 'removed 000-dup2.txt for --conflict skip test');
do_restore($backup_file, restore_dir => $restore_dir, conflict => 'skip');
ok_dirs_match($restore_dir, $root_dir);
# restored here: 000-dup1.txt + 000-dup2.txt + zero-length.txt
is_deeply([ sort @restored ], [ '000-dup1.txt', '000-dup2.txt', 'zero-length.txt' ], 'restore count == 3');

# Restore again, same restore_dir - should NOT die with --conflict overwrite
@restored = ();
ok(unlink("$restore_dir/000-dup2.txt"), 'removed 000-dup2.txt for --conflict overwrite test');
ok(utime(10000, 10000, "$restore_dir/test-file.txt"), "utime changed for restore_dir test-file.txt");
do_restore($backup_file, restore_dir => $restore_dir, conflict => 'overwrite');
ok_dirs_match($restore_dir, $root_dir);
ok(scalar(@restored) > 10, "restore_count > 10");

# Restore again, same restore_dir - should NOT die with --conflict update
@restored = ();
ok(unlink("$restore_dir/000-dup2.txt"), 'removed 000-dup2.txt for --conflict update test');
ok(utime(10000, 10000, "$restore_dir/test-file.txt"), "utime changed for restore_dir test-file.txt");
do_restore($backup_file, restore_dir => $restore_dir, conflict => 'update');
ok_dirs_match($restore_dir, $root_dir);
# restored here: 000-dup2.txt + test-file.txt + zero-length.txt
is_deeply([ sort @restored ], [ '000-dup2.txt', 'test-file.txt', 'zero-length.txt' ], 'restore count == 3');

done_testing;
