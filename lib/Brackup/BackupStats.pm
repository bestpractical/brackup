package Brackup::BackupStats;
use strict;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub print {
    print "# BACKUPS STATS: [TODO]\n";
}

sub note_stored_chunk {
    my ($self, $chunk) = @_;
}


1;
