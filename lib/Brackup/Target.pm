package Brackup::Target;

use strict;
use warnings;
use Brackup::InventoryDatabase;
use Carp qw(croak);

sub new {
    my ($class, $confsec) = @_;
    my $self = bless {}, $class;
    my $name = $confsec->name;
    $name =~ s!^TARGET:!! or die;

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

sub inventory_db {
    my $self = shift;
    return $self->{inv_db};
}

sub add_to_inventory {
    my ($self, $pchunk, $schunk) = @_;
    my $key  = $pchunk->inventory_key;
    my $db = $self->inventory_db;
    $db->set($key => join(" ", $schunk->backup_digest, $schunk->backup_length));
}

# return stored chunk, given positioned chunk, or undef.  no
# need to override this, unless you have a good reason.
sub stored_chunk_from_inventory {
    my ($self, $pchunk) = @_;
    my $key    = $pchunk->inventory_key;
    my $db     = $self->inventory_db;
    my $diglen = $db->get($key)
        or return undef;
    my ($digest, $length) = split /\s+/, $diglen;
    return Brackup::StoredChunk->new_from_inventory($pchunk, $digest, $length);
}


1;

