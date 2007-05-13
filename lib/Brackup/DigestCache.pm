package Brackup::DigestCache;
use strict;
use warnings;

# for now.  kinda ghetto.  could be anything...
# should 'have-a' instead of 'is-a' dict, and proxy
# the methods through.  but can do that later...
use base 'Brackup::Dict::SQLite';

sub new {
    my ($class, $root, $rconf) = @_;
    my $dir  = $root->path;
    my $file = $rconf->value('digestdb_file') || "$dir/" . default_filename();
    my $self = $class->SUPER::new("digest_cache", $file);
    # ...
    return $self;
}

sub default_filename { ".brackup-digest.db" };


1;

__END__

=head1 NAME

Brackup::DigestCache - cache digests of file and chunk contents

=head1 DESCRIPTION

The Brackup DigestCache caches the digests (currently SHA1) of files
and file chunks, to prevent untouched files from needing to be re-read
on subsequent, iterative backups.

The digest cache is I<purely> a cache.  It has no important data in it,
so don't worry about losing it.  Worst case if you lose it: subsequent
backups take longer while the digest cache is re-built.

=head1 DETAILS

=head2 File format

While designed to be abstract, the only supported digest cache format at
the moment is an SQLite database, stored in a single file.  The schema
is created automatically as needed... no database maintenance is required.

=head2 File location

The SQLite file is stored in either the location specified in a
L<Brackup::Root>'s [SOURCE] declaration in ~/.brackup.conf, as:

  [SOURCE:home]
  path = /home/bradfitz/
  # be explicit if you want:
  digestdb_file = /var/cache/brackup-brad/digest-cache-bradhome.db

Or, more commonly (and recommended), is to not specify it and accept
the default location, which is ".brackup-digest.db" in the root's
root directory.

  [SOURCE:home]
  path = /home/bradfitz/
  # this is the default:
  # digestdb_file = /home/bradfitz/.brackup-digest.db

=head2 SQLite Schema

This is made automatically for you, but if you want to look around in
it, the schema is:

  CREATE TABLE digest_cache (
       key TEXT PRIMARY KEY,
       value TEXT
  )

=head2 Keys & Values stored in the cache

B<Files digests:>  (see L<Brackup::File>)

 [rootname]path/to/file.txt:<ctime>,<mtime>,<size>,<inodenum>

B<Chunk digests:>  (see L<Brackup::PositionedChunk>)

 [rootname]path/to/file.txt:<ctime>,<mtime>,<size>,<inodenum>;o=<offset>;l=<length>

=head1 SEE ALSO

L<Brackup>




