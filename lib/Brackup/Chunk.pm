package Brackup::Chunk;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);
use File::Temp qw(tempfile);

#gpg --recipient 5E1B3EC5 --encrypt --output=file.enc file.orig
#gpg --output file.dec --decrypt file.enc

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{file}   = delete $opts{'file'};    # Brackup::File object
    $self->{offset} = delete $opts{'offset'};
    $self->{length} = delete $opts{'length'};

    croak("Unknown options: " . join(', ', keys %opts)) if %opts;
    croak("offset not numeric") unless $self->{offset} =~ /^\d+$/;
    croak("length not numeric") unless $self->{length} =~ /^\d+$/;
    return $self;
}

sub cache {
    my $self = shift;
    return $self->{file}->root->cache;
}

sub cachekey {
    my $self = shift;
    return join("-", $self->{file}->cachekey, $self->{offset}, $self->{length});
}

sub as_string {
    my $self = shift;
    return $self->{file}->as_string . "{off=$self->{offset},len=$self->{length}}";
}

sub root {
    my $self = shift;
    return $self->{file}->root;
}

sub chunkref {
    my $self = shift;

    my $root = $self->root;
    my $gpg_rcpt = $root->gpg_rcpt;

    my $fullpath = $self->{file}->fullpath;
    open(my $fh, $fullpath) or die "Failed to open $fullpath: $!\n";
    seek($fh, $self->{offset}, 0) or die "Couldn't seek: $!\n";
    my $data;
    read($fh, $data, $self->{length}) or die "Failed to read: $!\n";

    # non-encrypting case
    return \$data unless $gpg_rcpt;

    # FIXME: let users control where their temp files go?
    my ($tmpfh, $tmpfn) = tempfile();
    print $tmpfh $data or die "failed to print: $!";
    close $tmpfh or die "failed to close: $!\n";
	
    my ($etmpfh, $etmpfn) = tempfile();
    system("gpg", "--recipient", $gpg_rcpt, "--encrypt", "--output=$etmpfn", "--yes", $tmpfn)
	and die "Failed to run gpg: $!\n";
    open (my $enc_fh, $etmpfn) or die "Failed to open $etmpfn: $!\n";
    $data = do { local $/; <$enc_fh>; };

    return \$data;
}

sub _populate_lengthdigest {
    my $self = shift;
    unless ($self->_learn_lengthdigest_from_cache) {
	my $dataref = $self->chunkref;
	$self->_learn_lengthdigest($dataref);
    }
}

sub _learn_lengthdigest_from_cache {
    my $self = shift;

    my $cache = $self->cache;
    my $file = $self->{file};

    my $lendig = $cache->get($self->cachekey)
	or return 0;
    my ($length, $digest) = split(/\s+/, $lendig);
    $self->{backlength} = $length;
    $self->{digest} = $digest;
    return 1;
}

sub _learn_lengthdigest {
    my ($self, $dataref) = @_;
    $self->{backlength} = length $$dataref;
    $self->{digest} = "sha1-" . sha1_hex($$dataref);
    my $cache = $self->cache;
    $cache->set($self->cachekey, "$self->{backlength} $self->{digest}");
    1;
}

# the original length, pre-encryption
sub length {
    my $self = shift;
    return $self->{length};
}

# the length, either encrypted or not
sub backup_length {
    my $self = shift;
    return $self->{backlength} if $self->{backlength};
    $self->_populate_lengthdigest;
    return $self->{backlength};
}

# the digest, either encrypted or not
sub backup_digest {
    my $self = shift;
    return $self->{digest} if $self->{digest};
    $self->_populate_lengthdigest;
    return $self->{digest};
}

1;

