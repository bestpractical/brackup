package Brackup::Backup;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{root}    = delete $opts{root};     # Brackup::Root
    $self->{target}  = delete $opts{target};   # Brackup::Target

    $self->{saved_files} = [];   # list of hashrefs
    
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;

    return $self;
}

# returns 1 on success, or dies with error
sub backup {
    my ($self, $backup_file) = @_;

    my $root   = $self->{root};
    my $target = $self->{target};

    # store the files
    $root->foreach_file(sub {
	my ($file, $progress) = @_;  # a Brackup::File and Brackup::Progress

	print ($file->as_string . ":\n");

	$file->foreach_chunk(sub {
	    my $chunk = shift;  # a Brackup::Chunk object
	    print "  " . $chunk->as_string . "\n";
	    unless ($target->has_chunk($chunk)) {
		$target->store_chunk($chunk);
	    }
	});

	$self->add_file($file);
    });

    # write the metafile
    open (my $metafh, ">$backup_file") or die "Failed to open $backup_file for writing: $!\n";
    print $metafh $self->backup_header;
    $self->foreach_saved_file(sub {
	my $file = shift;
	print $metafh $file->as_rfc822;
    });
    close $metafh or die;

    my $contents;

    # store the metafile, encrypted, on the target
    if (my $rcpt = $self->{root}->gpg_rcpt) {
	my $encfile .= ".enc";
        system("gpg", "--recipient", $rcpt, "--encrypt", "--output=$encfile", "--yes", $backup_file)
	    and die "Failed to run gpg while encryping metafile: $!\n";
	$contents = contents_of($encfile);
	unlink $encfile;
    } else {
	$contents = contents_of($backup_file);
    }

    # store it on the target
    my $name = $self->{root}->publicname . "-" . $self->backup_time;
    $target->store_backup_meta($name, $contents);

    return 1;
}

sub contents_of {
    my $file = shift;
    open (my $fh, $file) or die "Failed to read contents of $file: $!\n";
    return do { local $/; <$fh>; };
}

sub backup_time {
    my $self = shift;
    return $self->{backup_time} ||= time();
}

sub backup_header {
    my $self = shift;
    my $ret = "";
    my $now = $self->backup_time;
    $ret .= "BackupTime: " . $now . " (" . localtime($now) . ")\n";
    $ret .= "RootName: " . $self->{root}->name . "\n";
    $ret .= "RootPath: " . $self->{root}->path . "\n";
    if (my $rcpt = $self->{root}->gpg_rcpt) {
	$ret .= "GPG-Recipient: $rcpt\n";
    }
    $ret .= "\n";
    return $ret; 
}

sub add_file {
    my ($self, $file) = @_;
    push @{ $self->{saved_files} }, $file;
}

sub foreach_saved_file {
    my ($self, $cb) = @_;
    foreach my $file (@{ $self->{saved_files} }) {
	$cb->($file);
    }
}

1;

