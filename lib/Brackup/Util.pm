package Brackup::Util;
use strict;
use warnings;
require Exporter;

use vars qw(@ISA @EXPORT_OK);
@ISA = ('Exporter');
@EXPORT_OK = ('tempfile', 'tempdir');

my $mainpid = $$;
my @TEMP_FILES = ();  # ([filename, caller], ...)

END {
    # will happen after File::Temp's cleanup
    foreach my $rec (@TEMP_FILES) {
        next unless -e $rec->[0];
        unlink($rec->[0]);
    }
}
use File::Temp ();

sub tempfile {
    my (@ret) = File::Temp::tempfile();
    my $from = join(" ", (caller())[0..2]);

    return wantarray ? @ret : $ret[0];
}

sub tempdir {
    return File::Temp::tempdir(@_);
}

1;
