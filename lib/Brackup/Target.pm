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

=back
