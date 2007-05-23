package Brackup::Root;
use strict;
use warnings;
use Carp qw(croak);
use File::Find;
use Brackup::DigestCache;
use Brackup::Util qw(tempfile);
use IPC::Open2;
use Symbol;

sub new {
    my ($class, $conf) = @_;
    my $self = bless {}, $class;

    ($self->{name}) = $conf->name =~ m/^SOURCE:(.+)$/
        or die "No backup-root name provided.";
    die "Backup-root name must be only a-z, A-Z, 0-9, and _." unless $self->{name} =~ /^\w+/;

    $self->{dir}        = $conf->path_value('path');
    $self->{gpg_path}   = $conf->value('gpg_path') || "/usr/bin/gpg";
    $self->{gpg_rcpt}   = $conf->value('gpg_recipient');
    $self->{chunk_size} = $conf->byte_value('chunk_size');
    $self->{ignore}     = [];

    $self->{merge_files_under}  = $conf->byte_value('merge_files_under');
    $self->{max_composite_size} = $conf->byte_value('max_composite_chunk_size') || 2**20;

    die "'max_composite_chunk_size' must be greater than 'merge_files_under'\n" unless
        $self->{max_composite_size} > $self->{merge_files_under};

    $self->{gpg_args}   = [];  # TODO: let user set this.  for now, not possible

    $self->{digcache}   = Brackup::DigestCache->new($self, $conf);
    $self->{digcache_file} = $self->{digcache}->backing_file;  # may be empty, if digest cache doesn't use a file

    $self->{noatime}    = $conf->value('noatime');
    return $self;
}

sub merge_files_under  { $_[0]{merge_files_under}  }
sub max_composite_size { $_[0]{max_composite_size} }

sub gpg_path {
    my $self = shift;
    return $self->{gpg_path};
}

sub gpg_args {
    my $self = shift;
    return @{ $self->{gpg_args} };
}

sub gpg_rcpt {
    my $self = shift;
    return $self->{gpg_rcpt};
}

# returns Brackup::DigestCache object
sub digest_cache {
    my $self = shift;
    return $self->{digcache};
}

sub chunk_size {
    my $self = shift;
    return $self->{chunk_size} || (64 * 2**20);  # default to 64MB
}

sub publicname {
    # FIXME: let users define the public (obscured) name of their roots.  s/porn/media/, etc.
    # because their metafile key names (which contain the root) aren't encrypted.
    return $_[0]{name};
}

sub name {
    return $_[0]{name};
}

sub ignore {
    my ($self, $pattern) = @_;
    push @{ $self->{ignore} }, $pattern;
}

sub path {
    return $_[0]{dir};
}

sub noatime {
    return $_[0]{noatime};
}

sub foreach_file {
    my ($self, $cb) = @_;

    chdir $self->{dir} or die "Failed to chdir to $self->{dir}";

    my %statcache; # file -> statobj

    find({
        no_chdir => 1,
        preprocess => sub {
            my $dir = $File::Find::dir;
            my @good_dentries;
          DENTRY:
            foreach my $dentry (@_) {
                next if $dentry eq "." || $dentry eq "..";

                my $path = "$dir/$dentry";
                $path =~ s!^\./!!;

                # skip the digest database file.  not sure if this is smart or not.
                # for now it'd be kinda nice to have, but it's re-creatable from
                # the backup meta files later, so let's skip it.
                next if $path eq $self->{digcache_file};

                # gpg seems to barf on files ending in whitespace, blowing
                # stuff up, so we just skip them instead...
                if ($path =~ /\s+$/) {
                    warn "Skipping file ending in whitespace: <$path>\n";
                    next;
                }

                my $statobj = File::stat::lstat($path);
                my $is_dir = -d _;

                foreach my $pattern (@{ $self->{ignore} }) {
                    next DENTRY if $path =~ /$pattern/;
                    next DENTRY if $is_dir && "$path/" =~ /$pattern/;
                }

                $statcache{$path} = $statobj;
                push @good_dentries, $dentry;
            }

            # to let it recurse into the good directories we didn't
            # already throw away:
            return sort @good_dentries;
        },

        wanted => sub {
            my $path = $_;
            $path =~ s!^\./!!;

            my $stat_obj = delete $statcache{$path};
            my $file = Brackup::File->new(root => $self,
                                          path => $path,
                                          stat => $stat_obj,
                                          );
            $cb->($file);
        },
    }, ".");
}

sub as_string {
    my $self = shift;
    return $self->{name} . "($self->{dir})";
}

sub du_stats {
    my $self = shift;

    my $show_all = $ENV{BRACKUP_DU_ALL};
    my @dir_stack;
    my %dir_size;
    my $pop_dir = sub {
        my $dir = pop @dir_stack;
        printf("%-20d%s\n", $dir_size{$dir} || 0, $dir);
        delete $dir_size{$dir};
    };
    my $start_dir = sub {
        my $dir = shift;
        unless ($dir eq ".") {
            my @parts = (".", split(m!/!, $dir));
            while (@dir_stack >= @parts) {
                $pop_dir->();
            }
        }
        push @dir_stack, $dir;
    };
    $self->foreach_file(sub {
        my $file = shift;
        my $path = $file->path;
        if ($file->is_dir) {
            $start_dir->($path);
            return;
        }
        if ($file->is_file) {
            my $size = $file->size;
            my $kB   = int($size / 1024) + ($size % 1024 ? 1 : 0);
            printf("%-20d%s\n", $kB, $path) if $show_all;
            $dir_size{$_} += $kB foreach @dir_stack;
        }
    });

    $pop_dir->() while @dir_stack;
}

# given data (scalar or scalarref), returns encrypted data
sub encrypt {
    my ($self, $data) = @_;
    my $gpg_rcpt = $self->gpg_rcpt
        or Carp::confess("Encryption not setup for this root");

    $data = \$data unless ref $data;

    my ($tmpfh, $tmpfn) = tempfile();
    print $tmpfh $$data
        or die "failed to print: $!";
    close $tmpfh
        or die "failed to close: $!\n";
    Carp::confess("size not right")
        unless -s $tmpfn == length $$data;

    my $cout = Symbol::gensym();
    my $cin = Symbol::gensym();

    my $pid = IPC::Open2::open2($cout, $cin,
        $self->gpg_path, $self->gpg_args,
        "--recipient", $gpg_rcpt,
        "--trust-model=always",
        "--batch",
        "--encrypt",
        "--output=-",  # Send output to stdout
        "--yes",
        $tmpfn
    );

    binmode $cout;

    my $ret = do { local $/; <$cout>; };

    waitpid($pid, 0);
    die "GPG failed: $!" if $? != 0; # If gpg return status is non-zero

    unlink($tmpfn);

    return $ret;
}

1;

__END__

=head1 NAME

Brackup::Root - describes the source directory (and options) for a backup

=head1 EXAMPLE

In your ~/.brackup.conf file:

  [SOURCE:bradhome]
  path = /home/bradfitz/
  gpg_recipient = 5E1B3EC5
  chunk_size = 64MB
  ignore = ^\.thumbnails/
  ignore = ^\.kde/share/thumbnails/
  ignore = ^\.ee/(minis|icons|previews)/
  ignore = ^build/
  noatime = 1

=head1 CONFIG OPTIONS

=over

=item B<path>

The directory to backup (recursively)

=item B<gpg_receipient>

The public key signature to encrypt data with.  See L<Brackup::Manual::Overview/"Using encryption">.

=item B<chunk_size>

In units of bytes, kB, MB, etc.  The max size of a chunk to be stored
on the target.  Files over this size are cut up into chunks of this
size or smaller.  The default is 64 MB if not specified.

=item B<ignore>

Perl5 regular expression of files not to backup.  You may have multiple ignore lines.

=item B<noatime>

If true, don't backup access times.  They're kinda useless anyway, and
just make the *.brackup metafiles larger.

=item B<merge_files_under>

In units of bytes, kB, MB, etc.  If files are under this size.  By
default this feature is off (value 0), purely because it's new, but 1
kB is a recommended size, and will probably be the default in the
future.  Set it to 0 to explicitly disable.

=item B<max_composite_chunk_size>

In units of bytes, kB, MB, etc.  The maximum size of a composite
chunk, holding lots of little files.  If this is too big, you'll waste
more space with future iterative backups updating files locked into
this chunk with unchanged chunks.

Recommended, and default value, is 1 MB.

=back
