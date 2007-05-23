# -*-perl-*-

use strict;
use Test::More tests => 15;

use Brackup::Test;
use FindBin qw($Bin);
use File::Temp qw(tempdir tempfile);

############### Backup

my ($digdb_fh, $digdb_fn) = tempfile();

my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data to backup exists");

my ($backup_file, $backup) =
    do_backup(
              with_confsec => sub {
                  my $csec = shift;
                  $csec->add("path",          $root_dir);
                  $csec->add("merge_files_under",    "1k");
                  $csec->add("max_composite_chunk_size",  "500k");
                  $csec->add("digestdb_file", $digdb_fn);
              },
              );

# see if dup files were only stored once
my %seen;
$backup->foreach_saved_file(sub {
    my ($file, $slist) = @_;
    return unless $file->path =~ /000-dup[12]\.txt$/;
    foreach my $sc (@$slist) {
        $seen{$sc->to_meta}++;
    }
});
is(scalar keys %seen, 1, "stored just one uniq copy of 000-dup[12]");
is((%seen)[-1], 2, "and stored it twice");
like((%seen)[0], qr/-/, "and it was stored in a range");



############### Restore

my $restore_dir = do_restore($backup_file);

ok_dirs_match($restore_dir, $root_dir);

