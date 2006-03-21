package Brackup::File;
# "everything is a file"
#  ... this class includes symlinks and directories

use strict;
use warnings;
use Carp qw(croak);
use File::stat ();
use Fcntl qw(S_ISREG S_ISDIR S_ISLNK);
use Digest::SHA1;
use Brackup::Chunk;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{root} = delete $opts{root};
    $self->{path} = delete $opts{path};
    $self->{stat} = delete $opts{stat};  # File::stat object
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;

    die "No root object provided." unless $self->{root} && $self->{root}->isa("Brackup::Root");
    die "No path provided." unless $self->{path};
    $self->{path} =~ s!^\./!!;

    return $self;
}

sub root {
    my $self = shift;
    return $self->{root};
}

# returns File::stat object
sub stat {
    my $self = shift;
    return $self->{stat} if $self->{stat};
    my $path = $self->fullpath;
    my $stat = File::stat::lstat($path);
    return $self->{stat} = $stat;
}

sub size {
    my $self = shift;
    return $self->stat->size;
}

sub is_dir {
    my $self = shift;
    return S_ISDIR($self->stat->mode);
}

sub is_link {
    my $self = shift;
    return S_ISLNK($self->stat->mode);
}

sub is_file {
    my $self = shift;
    return S_ISREG($self->stat->mode);
}

sub supported_type {
    my $self = shift;
    return $self->type ne "";
}

# returns "f", "l", or "d" like find's -type
sub type {
    my $self = shift;
    return "f" if $self->is_file;
    return "d" if $self->is_dir;
    return "l" if $self->is_link;
    return "";
}

sub fullpath {
    my $self = shift;
    return $self->{root}->path . "/" . $self->{path};
}

sub parts {
    return ("foo", "bar");
}

# a scalar that hopefully uniquely represents a single version of a file in time.
sub cachekey {
    my $self = shift;
    my $st   = $self->stat;
    return "[" . $self->{root}->name . "]" . $self->{path} . ":" . join(",", $st->ctime, $st->mtime, $st->size, $st->ino);
}

# iterate over chunks sized by the root's configuration
sub foreach_chunk {
    my ($self, $cb) = @_;
    my $root = $self->{root};
    my $chunk_size = $root->chunk_size;
    my $key  = $self->cachekey;

    # non-files don't have chunks
    return unless $self->is_file;

    my $offset = 0;
    my $size   = $self->size;

    my $min = sub { (sort { $a <=> $b } @_)[0] };

    while ($offset < $size) {
	my $len = $min->($chunk_size, $size - $offset);
	my $chunk = Brackup::Chunk->new(
					file   => $self,
					offset => $offset,
					length => $len,
					);
	$cb->($chunk);
	$offset += $len;
    }
}

sub full_digest {
    my $self = shift;
    return "" unless $self->is_file;

    my $db    = $self->{root}->digdb;
    my $key   = $self->cachekey;

    my $dig = $db->get($key);
    return $dig if $dig;

    my $sha1 = Digest::SHA1->new;
    my $path = $self->fullpath;
    open (my $fh, $path) or die "Couldn't open $path: $!\n";
    $sha1->addfile($fh);
    close($fh);

    $dig = "sha1-" . $sha1->hexdigest;
    $db->set($key, $dig);
    return $dig;
}

sub as_string {
    my $self = shift;
    my $type = $self->type;
    return "[" . $self->{root}->as_string . "] t=$type $self->{path}";
}

1;

