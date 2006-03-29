package Brackup::Restore;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    $self->{to}     = delete $opts{to};      # directory we're restoring to
    $self->{prefix} = delete $opts{prefix};  # directory/file filename prefix, or "" for all
    $self->{file}   = delete $opts{file};    # filename we're restoring from

    die "Destination directory doesn't exist" unless $self->{to} && -d $self->{to};
    die "Backup file doesn't exist"           unless $self->{file} && -f $self->{file};
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;
    return $self;
}

sub restore {
    my ($self) = @_;
    my $parser = $self->parser;
    use Data::Dumper;
    while (my $it = $parser->()) {
        print Dumper($it);
    }
}

# returns iterator subref which returns hashrefs or undef on EOF
sub parser {
    my $self = shift;
    open (my $fh, $self->{file}) or die "Failed to open metafile: $!";
    return sub {
        my $ret = {};
        my $last;  # scalarref to last item
        my $line;  #
        while (defined ($line = <$fh>)) {
            if ($line =~ /^([\w\-]+):\s*(.+)/) {
                $ret->{$1} = $2;
                $last = \$ret->{$1};
                next;
            }
            if ($line eq "\n") {
                return $ret;
            }
            if ($line =~ /^\s+(.+)/) {
                die "Can't continue line without start" unless $last;
                $$last .= " $1";
                next;
            }
            die "Unexpected line in metafile: $line";
        }
        return undef;
    }
}


1;

