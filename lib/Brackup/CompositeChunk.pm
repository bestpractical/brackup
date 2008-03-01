package Brackup::CompositeChunk;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA1 qw(sha1_hex);

use fields (
            'used_up',
            'max_size',
            'data',
            'target',
            'digest',  # memoized
            'finalized', # if we've written ourselves to the target yet
            'subchunks', # the chunks this composite chunk is made of
            );

sub new {
    my ($class, $root, $target) = @_;
    my $self = ref $class ? $class : fields::new($class);
    $self->{used_up}   = 0; # bytes
    $self->{finalized} = 0; # false
    $self->{max_size}  = $root->max_composite_size;
    $self->{data}      = '';
    $self->{target}    = $target;
    $self->{subchunks} = [];
    return $self;
}

sub append_little_chunk {
    my ($self, $schunk) = @_;
    die "ASSERT" if $self->{digest}; # its digest was already requested?

    my $from = $self->{used_up};
    $self->{used_up} += $schunk->backup_length;
    $self->{data}    .= ${ $schunk->chunkref };
    my $to = $self->{used_up};
    die "ASSERT" unless CORE::length($self->{data}) == $self->{used_up};

    $schunk->set_composite_chunk($self, $from, $to);
    push @{$self->{subchunks}}, $schunk;
}

sub digest {
    my $self = shift;
    return $self->{digest} ||= "sha1:" . Digest::SHA1::sha1_hex($self->{data});
}

sub can_fit {
    my ($self, $len) = @_;
    return $len <= ($self->{max_size} - $self->{used_up});
}

# return on success; die on any failure
sub finalize {
    my $self = shift;
    die "ASSERT" if $self->{finalized}++;

    $self->{target}->store_chunk($self)
        or die "chunk storage of composite chunk failed.\n";

    foreach my $schunk (@{$self->{subchunks}}) {
        $self->{target}->add_to_inventory($schunk->pchunk => $schunk);
    }

    return 1;
}

sub stored_chunk_from_dup_internal_raw {
    my ($self, $pchunk) = @_;
    my $ikey = $pchunk->inventory_key;
    foreach my $schunk (@{$self->{subchunks}}) {
        next unless $schunk->pchunk->inventory_key eq $ikey;
        # match!  found a duplicate within ourselves
        return $schunk->clone_but_for_pchunk($pchunk);
    }
    return undef;
}

# <duck-typing>
# make this duck-typed like a StoredChunk, so targets can store it
*backup_digest = \&digest;
sub backup_length {
    my $self = shift;
    return CORE::length($self->{data});
}
sub chunkref { return \ $_[0]->{data} }
sub inventory_value {
    die "ASSERT: don't expect this to be called";
}
# </duck-typing>

1;
