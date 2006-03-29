package Brackup::Target::Filesystem;
use strict;
use warnings;
use base 'Brackup::Target';
use File::Path;

sub new {
    my ($class, $confsec) = @_;
    my $self = bless {}, $class;
    $self->{path} = $confsec->path_value("path");
    return $self;
}

sub chunkpath {
    my ($self, $dig) = @_;
    my @parts;
    my $fulldig = $dig;
    $dig =~ s/^\w+://; # remove the "hashtype:" from beginning
    while (length $dig && @parts < 4) {
        $dig =~ s/^(.{1,4})//;
        push @parts, $1;
    }
    return $self->{path} . "/" . join("/", @parts) . "/$fulldig.chunk";
}

sub has_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;   # "sha1:sdfsdf" format scalar
    my $path = $self->chunkpath($dig);
    return -e $path;
}

sub store_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;
    my $blen = $chunk->backup_length;
    my $len = $chunk->length;

    my $path = $self->chunkpath($dig);
    my $dir = $path;
    $dir =~ s!/[^/]+$!!;
    unless (-d $dir) {
        File::Path::mkpath($dir) or die "Failed to mkdir: $dir: $!\n";
    }
    open (my $fh, ">$path") or die "Failed to open $path for writing: $!\n";
    print $fh ${ $chunk->chunkref };
    close($fh) or die "Failed to close $path\n";
    return 1;
}

sub store_backup_meta {
    my ($self, $name, $file) = @_;
    my $dir = "$self->{path}/backups/";
    unless (-d $dir) {
        mkdir $dir or die "Failed to mkdir $dir: $!\n";
    }
    open (my $fh, ">$dir/$name.brackup") or die;
    print $fh $file;
    close $fh or die;
    return 1;
}

1;

