# -*-perl-*-

use strict;
use Test::More tests => 9;

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
                            );

############### Add an orphan chunk

my $orphan_chunks_count = int(rand 10);
for (1..$orphan_chunks_count) {
    my $chunk = Brackup::StoredChunk->new;
    $chunk->{_chunkref} = \ "foobar $_";
    $target->store_chunk($chunk);
}

############### Do garbage collection

my $removed_count = $target->gc;
ok($removed_count == $orphan_chunks_count, "all orphan chunks removed");

__END__
