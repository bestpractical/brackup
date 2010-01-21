# -*-perl-*-

use strict;
use Test::More tests => 11;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

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
                                $tsec->add("type", 'Filesystem');
                                $tsec->add("inventorydb_type", $ENV{BRACKUP_TEST_INVENTORYDB_TYPE} || 'SQLite');
                            }
                            );

############### Add orphan chunks

my $orphan_chunks_count = int(rand 10) + 1;
Brackup::Test::add_orphan_chunks($backup->{root}, $target, $orphan_chunks_count);

############### Do garbage collection

my $removed_count = eval { $target->gc };
is($@, '', "gc successful");
is($removed_count, $orphan_chunks_count, "all orphan chunks removed");

__END__
