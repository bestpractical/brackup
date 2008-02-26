package Brackup::Target::Ftp;
use strict;
use warnings;
use base 'Brackup::Target::Filebased';
use File::Basename;
use Net::FTP;

sub new {
    my ($class, $confsec) = @_;
    my $self = $class->SUPER::new($confsec);

    $self->{ftp_host} = $confsec->value("ftp_host") or die 'No "ftp_host"';
    $self->{ftp_user} = $confsec->value("ftp_user") or die 'No "ftp_user"';
    $self->{ftp_password} = $confsec->value("ftp_password") or
        die 'No "ftp_password"';
    $self->{path} = $confsec->value("path") or
        die 'No path specified';

    $self->_common_new;

    return $self;
}

sub new_from_backup_header {
    my ($class, $header) = @_;
    my $self = bless {}, $class;

    $self->{ftp_host} = $ENV{FTP_HOST} || $header->{'FtpHost'};
    $self->{ftp_user} = $ENV{FTP_USER} || $header->{'FtpUser'};
    $self->{ftp_password} = $ENV{FTP_PASSWORD} or
        die "FTP_PASSWORD missing in environment";
    $self->{path} = $header->{'BackupPath'} or
        die "No BackupPath specified in the backup metafile.\n";

    $self->_common_new;

    return $self;
}

sub _common_new {
    my ($self) = @_;

    $self->{ftp} = Net::FTP->new($self->{ftp_host}) or die $@;
    $self->{ftp}->login($self->{ftp_user}, $self->{ftp_password});
    $self->{ftp}->binary();
}

sub backup_header {
    my ($self) = @_;
    return {
        "BackupPath" => $self->{path},
        "FtpHost" => $self->{ftp_host},
        "FtpUser" => $self->{ftp_user},
    };
}

sub nocolons {
    # We never know what operating system is at the other end, thus never use
    # colons.
    return 1;
}

sub _ls {
    my ($self, $path) = @_;

    my $result = $self->{ftp}->ls($self->metapath());
    unless (defined($result)) {
        die "Listing failed for $path: " . $self->{ftp}->message;
    }

    return $result;
}

sub _size {
    my ($self, $path) = @_;

    my $size = $self->{ftp}->size($path);
    unless (defined($size)) {
        die "Chunk output file $path does not exist.";
    }

    return $size;
}

sub _put {
    my ($self, $path, $content) = @_;
    my $dir = dirname($path);

    # Make sure directory exists.
    $self->{ftp}->mkdir($dir, 1)
        or die "Creating directory $dir failed: " . $self->{ftp}->message;

    open(my $fh, '<', \$content) or die $!;
    binmode($fh);
    $self->{ftp}->put($fh, $path)
        or die "Writing file $path failed: " . $self->{ftp}->message;
    close($fh) or die "Failed to close";
}

sub _get {
    my ($self, $path) = @_;
    my $content;

    open(my $fh, '>', \$content) or die $!;
    binmode($fh);
    $self->{ftp}->get($path, $fh)
        or die "Reading file $path failed: " . $self->{ftp}->message;
    close($fh) or die "Failed to close";

    return \$content;
}

sub _delete {
    my ($self, $path) = @_;
    $self->{ftp}->delete($path)
        or die "Removing file $path failed: " . $self->{ftp}->message;
}

sub _recurse {
    my ($self, $path, $maxdepth, $match) = @_;
    return if $maxdepth < 0;
    foreach ($self->_ls($path)) {
        if ($match->($_)) {
            $self->_recurse($_, $maxdepth - 1, $match);
        }
    }
}

sub chunkpath {
    my ($self, $dig) = @_;
    return $self->{path} . '/' . $self->SUPER::chunkpath($dig);
}

sub metapath {
    my ($self, $name) = @_;
    return $self->{path} . '/' . $self->SUPER::metapath($name);
}

sub load_chunk {
    my ($self, $dig) = @_;
    return $self->_get($self->chunkpath($dig));
}

sub store_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;
    my $path = $self->chunkpath($dig);

    my $chunkref = $chunk->chunkref;
    $self->_put($path, $$chunkref);

    my $actual_size = $self->_size($path);
    my $expected_size = length $$chunkref;
    unless ($actual_size == $expected_size) {
        die "Chunk $path incompletely written to disk: size is " .
            "$actual_size, expecting $expected_size\n";
    }

    return 1;
}

sub delete_chunk {
    my ($self, $dig) = @_;
    $self->_delete($self->chunkpath($dig));
}

# returns a list of names of all chunks
sub chunks {
    my ($self) = @_;
    my @chunks;

    $self->_recurse($self->{path}, 2, sub {
        my ($path) = @_;
        my $filename = basename($path);

        if ($path =~ m/\.chunk$/) {
            $filename =~ s/\.chunk$//;
            push @chunks, $filename;
            return 0;
        }

        return $filename ne 'backups';
    });

    return @chunks;
}

sub store_backup_meta {
    my ($self, $name, $content) = @_;
    $self->_put($self->metapath("$name.brackup"), $content);
    return 1;
}

sub backups {
    my ($self) = @_;
    my $list = $self->_ls($self->metapath());

    my @ret = ();
    foreach (@$list) {
        my $fn = basename($_);
        next unless $fn =~ s/\.brackup$//;

        my $size = $self->_size($_);
        my $mtime = $self->{ftp}->mdtm($_);
        unless (defined $mtime) {
            die "Getting mtime of $_ failed: " . $self->{ftp}->message;
        }

        push @ret, Brackup::TargetBackupStatInfo->new($self, $fn,
                                                      time => $mtime,
                                                      size => $size);
    }

    return @ret;
}

# downloads the given backup name to the current directory (with
# *.brackup extension) or to the specified location
sub get_backup {
    my ($self, $name, $output_file) = @_;
    my $path = $self->metapath("$name.brackup");

	$output_file ||= "$name.brackup";

    open(my $out, '>', $output_file)
        or die "Failed to open $output_file: $!\n";
    $self->{ftp}->get($path, $out)
        or die "Reading file $path failed: " . $self->{ftp}->message;
    close($out) or die $!;

    return 1;
}

sub delete_backup {
    my ($self, $name) = @_;
    $self->_delete($self->metapath("$name.brackup"));
    return 1;
}

1;


=head1 NAME

Brackup::Target::Ftp - backup to an FTP server

=head1 DESCRIPTION

Back up to an FTP server.

=head1 EXAMPLE

In your ~/.brackup.conf file:

  [TARGET:nfs_in_garage]
  type = Ftp
  path = .
  ftp_host = ftp.domain.tld
  ftp_user = user
  ftp_password = password

=head1 CONFIG OPTIONS

=over

=item B<type>

Must be "B<Ftp>".

=item B<path>

Server-side path, can be ".".

=item B<ftp_host>

FTP server host, optionally with port (host:port).

=item B<ftp_user>

Username to use.

=item B<ftp_password>

Password to use.

=back

=head1 SEE ALSO

L<Brackup::Target>
