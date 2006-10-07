package Brackup::Chunk;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);
use File::Temp qw(tempfile);

# fields
# ------
#   file            the Brackup::File object
#   offset
#   length
# sometimes:
#   digest          if calculated "type:hex"
#   _chunkref       if calculated, scalarref
#   backlength      if calculated
#   will_need_data  see function of same name below for details

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

sub file {
    my $self = shift;
    return $self->{file};
}

sub root {
    my $self = shift;
    return $self->file->root;
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
    if ($self->{will_need_data}) {
        die "failed to get length/digest of chunk data" unless
            $self->_learn_lengthdigest_from_data($self->chunkref);
    } else {
        die "failed to get length/digest of chunk" unless
            $self->_learn_lengthdigest_from_cache ||
            $self->_learn_lengthdigest_from_data($self->chunkref);
    }
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
        Carp::confess("Digest changed!\n");
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

# a way for the backup class to signal that this chunk doesn't exist
# on the target and we'll more than likely be asked for its data next.
# it could be a --dry-run, though, so we shouldn't prep the data
# already.  however, next time we're asked for the backup_digest
# or backup_length, they damn well match the chunkref we later give it,
# regardless of which order the target driver asks for stuff in.  for instance,
#
#   ($data, $dig, $len) = ($chunk->data, $chunk->backup_digest, $chunk->backup_length)
#
# would work without this.  but a target driver might do:
#
#   ($dig, $len, $data) = ($chunk->backup_digest, $chunk->backup_length, $chunk->data)
#
# and get the old digest/length before the data calls then changes
# those.  (remember that with encryption, the digest/length of the
# encrypted chunk changes each time)
#
# so this is where we forget any cached data and set the 'will_need_data' flag
# so the cached isn't used in the future.

sub will_need_data {
    my $self = shift;
    delete $self->{digest};
    delete $self->{backlength};
    $self->{will_need_data} = 1;
}

1;
