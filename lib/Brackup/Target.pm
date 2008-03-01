package Brackup::Target;

use strict;
use warnings;
use Brackup::InventoryDatabase;
use Brackup::TargetBackupStatInfo;
use Brackup::Util 'tempfile';
use Carp qw(croak);

sub new {
    my ($class, $confsec) = @_;
    my $self = bless {}, $class;
    my $name = $confsec->name;
    $name =~ s!^TARGET:!! or die;

    $self->{keep_backups} = $confsec->value("keep_backups");
    $self->{inv_db} =
        Brackup::InventoryDatabase->new($confsec->value("inventory_db") ||
                                        "$ENV{HOME}/.brackup-target-$name.invdb");

    return $self;
}

# return hashref of key/value pairs you want returned to you during a restore
# you should include anything you need to restore.
# keys should only contain \w
sub backup_header {
    return {}
}

# returns bool
sub has_chunk {
    my ($self, $chunk) = @_;
    die "ERROR: has_chunk not implemented in sub-class $self";
}

# returns true on success, or returns false or dies otherwise.
sub store_chunk {
    my ($self, $chunk) = @_;
    die "ERROR: store_chunk not implemented in sub-class $self";
}

# returns true on success, or returns false or dies otherwise.
sub delete_chunk {
    my ($self, $chunk) = @_;
    die "ERROR: delete_chunk not implemented in sub-class $self";
}

# returns a list of names of all chunks
sub chunks {
    my ($self) = @_;
    die "ERROR: chunks not implemented in sub-class $self";
}

sub inventory_db {
    my $self = shift;
    return $self->{inv_db};
}

sub add_to_inventory {
    my ($self, $pchunk, $schunk) = @_;
    my $key  = $pchunk->inventory_key;
    my $db = $self->inventory_db;
    $db->set($key => $schunk->inventory_value);
}

# return stored chunk, given positioned chunk, or undef.  no
# need to override this, unless you have a good reason.
sub stored_chunk_from_inventory {
    my ($self, $pchunk) = @_;
    my $key    = $pchunk->inventory_key;
    my $db     = $self->inventory_db;
    my $invval = $db->get($key)
        or return undef;
    return Brackup::StoredChunk->new_from_inventory_value($pchunk, $invval);
}

# return a list of TargetBackupStatInfo objects representing the
# stored backup metafiles on this target.
sub backups {
    my ($self) = @_;
    die "ERROR: backups method not implemented in sub-class $self";
}

# downloads the given backup name to the current directory (with
# *.brackup extension)
sub get_backup {
    my ($self, $name) = @_;
    die "ERROR: get_backup method not implemented in sub-class $self";
}

# deletes the given backup from this target
sub delete_backup {
    my ($self, $name) = @_;
    die "ERROR: delete_backup method not implemented in sub-class $self";
}

# removes old metafiles from this target
sub prune {
    my ($self, %opt) = @_;

    my $keep_backups = $self->{keep_backups} || $opt{keep_backups}
        or die "ERROR: keep_backups option not set\n";
    die "ERROR: keep_backups option must be at least 1\n"
        unless $keep_backups > 0;

    # select backups to delete
    my (%backups, @backups_to_delete) = ();
    foreach my $backup_name (map {$_->filename} $self->backups) {
        $backup_name =~ /^(.+)-\d+$/;
        $backups{$1} ||= [];
        push @{ $backups{$1} }, $backup_name;
    }
    foreach my $source (keys %backups) {
        my @b = reverse sort @{ $backups{$source} };
        push @backups_to_delete, splice(@b, ($keep_backups > $#b+1) ? $#b+1 : $keep_backups);
    }

    unless ($opt{dryrun}) {
         $self->delete_backup($_) for @backups_to_delete;
    }
    return scalar @backups_to_delete;
}

# removes orphaned chunks in the target
sub gc {
    my ($self, %opt) = @_;

    # get all chunks and then loop through metafiles to detect
    # referenced ones
    my %chunks = map {$_ => 1} $self->chunks;
    my $tempfile = +(tempfile())[1];
    BACKUP: foreach my $backup ($self->backups) {
        $self->get_backup($backup->filename, $tempfile);
        my $parser = Brackup::Metafile->open($tempfile);
        $parser->readline;  # skip header
        ITEM: while (my $it = $parser->readline) {
            next ITEM unless $it->{Chunks};
            my @item_chunks = map { (split /;/)[3] } grep { $_ } split(/\s+/, $it->{Chunks} || "");
            delete $chunks{$_} for (@item_chunks);
        }
    }
    my @orphaned_chunks = keys %chunks;

    # remove orphaned chunks
    unless ($opt{dryrun}) {
         $self->delete_chunk($_) for @orphaned_chunks;
    }
    return scalar @orphaned_chunks;
}



1;

__END__

=head1 NAME

Brackup::Target - describes the destination for a backup

=head1 EXAMPLE

In your ~/.brackup.conf file:

  [TARGET:amazon]
  type = Amazon
  aws_access_key_id  = ...
  aws_secret_access_key =  ....

=head1 GENERAL CONFIG OPTIONS

=over

=item B<type>

The driver for this target type.  The type B<Foo> corresponds to the Perl module Brackup::Target::B<Foo>.

As such, the only valid options for type, if you're just using the
Target modules that come with the Brackup core, are:

B<Amazon> -- see L<Brackup::Target::Amazon> for configuration details

B<Filesystem> -- see L<Brackup::Target::Filesystem> for configuration details

=item B<keep_backups>

The number of recent backups to keep when running I<brackup-target prune>.

=back
