# -*-perl-*-

use strict;
use Test::More;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

############### Backup

my $arguments = '--from test_root --to test_target -v';
my ($digdb_fh, $digdb_fn) = tempfile();
close($digdb_fh);
my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data to backup exists");
my ($backup_file, $brackup, $target, $stats) = do_backup(
                            with_confsec => sub {
                                my $csec = shift;
                                $csec->add("path",          $root_dir);
                                $csec->add("chunk_size",    "2k");
                                $csec->add("digestdb_file", $digdb_fn);
                                $csec->add("webhook_url",   $ENV{BRACKUP_TEST_WEBHOOK_URL})
                                    if $ENV{BRACKUP_TEST_WEBHOOK_URL};
                            },
                            with_arguments => $arguments,
                            );

my $stats_hash = $stats->as_hash;
is($stats_hash->{arguments}, $arguments, '$stats_hash arguments set correctly');
for (qw(start_time end_time run_times memory_usage files)) {
  ok($stats_hash->{$_}, "\$stats_hash $_ set");
}
for (qw(run_times memory_usage)) {
  ok(@{$stats_hash->{$_}}, "\$stats_hash $_ count non-zero: " . scalar(@{$stats_hash->{$_}}));
}
is($stats_hash->{files}->{files_checked_count}, 17, 'stats files_checked_count ok: ' . $stats_hash->{files}->{files_checked_count});
is($stats_hash->{files}->{files_uploaded_count}, 11, 'stats files_uploaded_count ok: ' . $stats_hash->{files}->{files_uploaded_count});

#use Data::Dump qw(pp);
#pp $stats_hash;
#$stats->print;

done_testing;

