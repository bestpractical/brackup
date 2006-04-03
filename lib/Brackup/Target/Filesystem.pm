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

sub new_from_backup_header {
    my ($class, $header) = @_;
    my $self = bless {}, $class;
    $self->{path} = $header->{"BackupPath"} or
        die "No BackupPath specified in the backup metafile.\n";
    unless (-d $self->{path}) {
        die "Restore path $self->{path} doesn't exist.\n";
    }
    return $self;
}

sub backup_header {
    my $self = shift;
    return {
        "BackupPath" => $self->{path},
    };
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

sub load_chunk {
    my ($self, $dig) = @_;
    my $path = $self->chunkpath($dig);
    open (my $fh, $path) or die "Error opening $path to load chunk: $!";
    my $chunk = do { local $/; <$fh>; };
    return \$chunk;
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
    my $chunkref = $chunk->chunkref;
    print $fh $$chunkref;
    close($fh) or die "Failed to close $path\n";

    my $actual_size   = -s $path;
    my $expected_size = length $$chunkref;
    unless ($actual_size == $expected_size) {
        die "Chunk was written to disk wrong:  size is $actual_size, expecting $expected_size\n";
    }

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

