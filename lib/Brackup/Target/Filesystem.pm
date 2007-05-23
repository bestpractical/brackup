package Brackup::Target::Filesystem;
use strict;
use warnings;
use base 'Brackup::Target';
use File::Path;
use File::stat ();


sub new {
    my ($class, $confsec) = @_;
    my $self = $class->SUPER::new($confsec);
    $self->{path} = $confsec->path_value("path");
    $self->{nocolons} = $confsec->value("no_filename_colons");
    $self->{nocolons} = ($^O eq 'MSWin32') unless defined $self->{nocolons}; # LAME: Make it work on Windows
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

sub _diskpath {
    my ($self, $dig, $ext) = @_;
    my @parts;
    my $fulldig = $dig;
    $dig =~ s/^\w+://; # remove the "hashtype:" from beginning
    $fulldig =~ s/:/./g if $self->{nocolons}; # Convert colons to dots if we've been asked to
    while (length $dig && @parts < 4) {
        $dig =~ s/^(.{1,4})//;
        push @parts, $1;
    }
    return $self->{path} . "/" . join("/", @parts) . "/$fulldig.$ext";
}

sub chunkpath {
    my ($self, $dig) = @_;
    return $self->_diskpath($dig, "chunk");
}

sub has_chunk_of_handle {
    my ($self, $handle) = @_;
    my $dig = $handle->digest;  # "sha1:sdfsdf" format scalar
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

    my $path = $self->chunkpath($dig);
    my $dir = $path;
    $dir =~ s!/[^/]+$!!;
    unless (-d $dir) {
        File::Path::mkpath($dir) or die "Failed to mkdir: $dir: $!\n";
    }
    open (my $fh, ">$path") or die "Failed to open $path for writing: $!\n";
    binmode($fh);
    my $chunkref = $chunk->chunkref;
    print $fh $$chunkref;
    close($fh) or die "Failed to close $path\n";

    my $actual_size   = -s $path;
    my $expected_size = length $$chunkref;
    unless (defined($actual_size)) {
        die "Chunk output file $path does not exist. Do you need to set no_filename_colons=1?";
    }
    unless ($actual_size == $expected_size) {
        die "Chunk $path was written to disk wrong:  size is $actual_size, expecting $expected_size\n";
    }

    return 1;
}

sub _metafile_dir {
    return $_[0]->{path}."/backups/";
}

sub store_backup_meta {
    my ($self, $name, $file) = @_;
    my $dir = $self->_metafile_dir;
    unless (-d $dir) {
        mkdir $dir or die "Failed to mkdir $dir: $!\n";
    }
    open (my $fh, ">$dir/$name.brackup") or die;
    print $fh $file;
    close $fh or die;
    return 1;
}

sub backups {
    my ($self) = @_;

    my $dir = $self->_metafile_dir;
    return () unless -d $dir;

    opendir(my $dh, $dir) or
        die "Failed to open $dir: $!\n";

    my @ret = ();
    while (my $fn = readdir($dh)) {
        next unless $fn =~ s/\.brackup$//;
        my $stat = File::stat::stat("$dir/$fn.brackup");
        push @ret, Brackup::TargetBackupStatInfo->new($self, $fn,
                                                      time => $stat->mtime,
                                                      size => $stat->size);
    }
    closedir($dh);
    return @ret;
}

# downloads the given backup name to the current directory (with
# *.brackup extension)
sub get_backup {
    my ($self, $name) = @_;
    my $dir  = $self->_metafile_dir;
    my $file = "$dir/$name.brackup";
    die "File doesn't exist: $file" unless -e $file;
    open(my $in,  $file)            or die "Failed to open $file: $!\n";
    open(my $out, ">$name.brackup") or die "Failed to open $name.brackup: $!\n";
    my $buf;
    my $rv;
    while ($rv = sysread($in, $buf, 128*1024)) {
        my $outv = syswrite($out, $buf);
        die "copy error" unless $outv == $rv;
    }
    die "copy error" unless defined $rv;
    return 1;
}

1;


=head1 NAME

Brackup::Target::Filesystem - backup to a locally mounted filesystem

=head1 DESCRIPTION

Back up to an NFS or Samba server, another disk array (external storage), etc.

=head1 EXAMPLE

In your ~/.brackup.conf file:

  [TARGET:nfs_in_garage]
  type = Filesystem
  path = /mnt/nfs-garage/brackup/

=head1 CONFIG OPTIONS

=over

=item B<type>

Must be "B<Filesystem>".

=item B<path>

Path to backup to.

=back

=head1 SEE ALSO

L<Brackup::Target>
