package Brackup::Util;
use strict;
use warnings;
require Exporter;

use vars qw(@ISA @EXPORT_OK);
@ISA = ('Exporter');
@EXPORT_OK = qw(tempfile tempdir slurp valid_params noclobber_filename io_print_to_fh);

use File::Path qw();
use Carp;
use Fcntl qw(O_RDONLY);

my $mainpid = $$;
my $_temp_directory;

END {
    # will happen after File::Temp's cleanup
    if ($$ == $mainpid and $_temp_directory) {
        File::Path::rmtree($_temp_directory, 0, 1);
    }
}
use File::Temp ();

sub _get_temp_directory {
    # Create temporary directory if we need one. By default, all temporary
    # files will be placed in it.
    unless (defined($_temp_directory)) {
        $_temp_directory = File::Temp::tempdir(CLEANUP => 1);
    }

    return $_temp_directory;
}

sub tempfile {
    my (@ret) = File::Temp::tempfile(DIR => _get_temp_directory());
    return wantarray ? @ret : $ret[0];
}

# Utils::tempdir() accepts the same options as File::Temp::tempdir.
sub tempdir {
    my %options = @_;
    $options{DIR} ||= _get_temp_directory();
    return File::Temp::tempdir(%options);
}

sub slurp {
    my $file = shift;
    sysopen(my $fh, $file, O_RDONLY) or die "Failed to open $file: $!";
    return do { local $/; <$fh>; }
}

sub valid_params {
    my ($vlist, %uarg) = @_;
    my %ret;
    $ret{$_} = delete $uarg{$_} foreach @$vlist;
    croak("Bogus options: " . join(', ', sort keys %uarg)) if %uarg;
    return %ret;
}

# Uniquify the given filename to avoid clobbering existing files
sub noclobber_filename {
    my ($filename) = @_;
    return $filename if ! -e $filename;
    for (my $i = 1; ; $i++) {
        return "$filename.$i" if ! -e "$filename.$i";
    }
}

# Prints all data from an IO::Handle to a filehandle
sub io_print_to_fh {
    my ($io_handle, $fh) = @_;
    my $buf;
    my $bytes = 0;
    while($io_handle->read($buf, 4096)) {
        print $fh $buf;
        $bytes += length $buf;
    }
    return $bytes;
}

1;

# vim:sw=4
