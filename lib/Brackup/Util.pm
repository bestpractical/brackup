package Brackup::Util;
use strict;
use warnings;
require Exporter;

use vars qw(@ISA @EXPORT_OK);
@ISA = ('Exporter');
@EXPORT_OK = qw(tempfile tempdir slurp valid_params);

my $mainpid = $$;
my @TEMP_FILES = ();  # ([filename, caller], ...)

END {
    # will happen after File::Temp's cleanup
    if ($$ == $mainpid) {
        foreach my $rec (@TEMP_FILES) {
            next unless -e $rec->[0];
            unlink($rec->[0]);
        }
    }
}
use File::Temp ();

sub tempfile {
    my (@ret) = File::Temp::tempfile();
    my $from = join(" ", (caller())[0..2]);
    push @TEMP_FILES, [$ret[1], $from];
    return wantarray ? @ret : $ret[0];
}

sub tempdir {
    return File::Temp::tempdir(@_);
}

sub slurp {
    my $file = shift;
    open(my $fh, $file) or die "Failed to open $file: $!\n";
    return do { local $/; <$fh>; }
}

sub valid_params {
    my ($vlist, %uarg) = @_;
    my %ret;
    $ret{$_} = delete $uarg{$_} foreach @$vlist;
    croak("Bogus options: " . join(', ', sort keys %uarg)) if %uarg;
    return %ret;
}

1;
