package Brackup::Chunk;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);
use File::Temp qw(tempfile);

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

sub digdb {
    my $self = shift;
    return $self->{file}->root->digdb;
}

# to the format used by the metafile
sub to_meta {
    my $self = shift;
    return join(";", $self->{offset}, $self->{length}, $self->backup_length, $self->backup_digest);
}

sub cachekey {
    my $self = shift;
    return join("-", $self->{file}->full_digest, $self->{offset}, $self->{length}, $self->root->gpg_rcpt || "");
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
    return $self->{_chunkref} if $self->{_chunkref};

    my $data;
    my $dataref_with_learning = sub {
        # record the encrypted/
        $self->_learn_lengthdigest_from_data(\$data);
        return $self->{_chunkref} = \$data;
    };

    my $root = $self->root;
    my $gpg_rcpt = $root->gpg_rcpt;

    my $fullpath = $self->{file}->fullpath;
    open(my $fh, $fullpath) or die "Failed to open $fullpath: $!\n";
    seek($fh, $self->{offset}, 0) or die "Couldn't seek: $!\n";
    read($fh, $data, $self->{length}) or die "Failed to read: $!\n";

    # non-encrypting case
    return $dataref_with_learning->() unless $gpg_rcpt;

    # FIXME: let users control where their temp files go?
    my ($tmpfh, $tmpfn) = tempfile();
    print $tmpfh $data or die "failed to print: $!";
    close $tmpfh or die "failed to close: $!\n";
    die "size not right" unless -s $tmpfn == $self->{length};

    my ($etmpfh, $etmpfn) = tempfile();

    system($self->root->gpg_path, $self->root->gpg_args,
           "--recipient", $gpg_rcpt,
           "--trust-model=always",
           "--batch",
           "--encrypt",
           "--output=$etmpfn",
           "--yes", $tmpfn)
        and die "Failed to run gpg: $!\n";
    open (my $enc_fh, $etmpfn) or die "Failed to open $etmpfn: $!\n";
    $data = do { local $/; <$enc_fh>; };

    return $dataref_with_learning->();
}

# lose the chunkref data
sub forget_chunkref {
    my $self = shift;
    delete $self->{_chunkref};
}

sub _populate_lengthdigest {
    my $self = shift;
    die "failed to get length/digest of chunk" unless
        $self->_learn_lengthdigest_from_cache ||
        $self->_learn_lengthdigest_from_data($self->chunkref);
}

sub _learn_lengthdigest_from_cache {
    my $self = shift;

    my $db   = $self->digdb or die "No digest database?";
    my $file = $self->{file};

    my $lendig = $db->get($self->cachekey)
        or return 0;
    my ($length, $digest) = split(/\s+/, $lendig);

    return 0 unless $digest =~ /^sha1:/;

    $self->{backlength} = $length;
    $self->{digest}     = $digest;
    return 1;
}

sub _learn_lengthdigest_from_data {
    my ($self, $dataref) = @_;
    my $old_digest = $self->{digest};

    $self->{backlength} = length $$dataref;
    $self->{digest}     = "sha1:" . sha1_hex($$dataref);

    # be paranoid about this changing
    if ($old_digest && $old_digest ne $self->{digest}) {
        die "Digest changed!\n";
    }

    $self->digdb->set($self->cachekey, "$self->{backlength} $self->{digest}");
    return 1;
}

# the original length, pre-encryption
sub length {
    my $self = shift;
    return $self->{length};
}

# the length, either encrypted or not
sub backup_length {
    my $self = shift;
    return $self->{backlength} if defined $self->{backlength};
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

