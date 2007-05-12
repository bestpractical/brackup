package Brackup::GPGProcManager;
use strict;
use warnings;
use Brackup::GPGProcess;

sub new {
    my ($class, $iter) = @_;
    return bless {
        chunkiter => $iter,
        procs     => {},  # "addr(pchunk)" => GPGProcess
    }, $class;
}

sub enc_chunkref_of {
    my ($self, $pchunk) = @_;

    my $proc = $self->{procs}{$pchunk} ||=
        Brackup::GPGProcess->new($pchunk);

    # TODO: increment counters of outstanding stuff, etc.
    my $cref = $proc->chunkref;

    # cleanup
    delete $self->{procs}{$pchunk};

    return $cref;
}


1;

