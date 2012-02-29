package Brackup::BackupStats;
use strict;
use Carp;

sub new {
    my $class = shift;
    my %opts = @_;
    my $arguments = delete $opts{arguments};
    croak("Unknown options: " . join(', ', keys %opts)) if %opts;

    my $self = {
        start_time  => time,
        ts          => Brackup::BackupStats::OrderedData->new,
        data        => Brackup::BackupStats::LabelledData->new,
    };
    $self->{arguments} = $arguments if $arguments;

    if (eval { require GTop }) {
        $self->{gtop} = GTop->new;
        $self->{gtop_max} = 0;
        $self->{gtop_data} = Brackup::BackupStats::OrderedData->new;
    }

    return bless $self, $class;
}

sub print {
    my $self = shift;
    my $stats_file = shift;

    $self->end;
  
    # Reset iterators
    $self->reset;

    my $fh;
    if ($stats_file) {
        open $fh, ">$stats_file" 
            or die "Failed to open stats file '$stats_file': $!";
    }
    else {
        $fh = *STDOUT;
    }

    my $hash = $stats_file ? '' : '# ';
    print $fh "${hash}BACKUPS STATS:\n";
    print $fh "${hash}\n";

    my $start_time = $self->{start_time};
    my $end_time   = $self->{end_time};
    my $fmt = "${hash}%-39s %s\n";
    printf $fh $fmt, 'Start Time:',       scalar localtime $start_time;
    printf $fh $fmt, 'End Time:',         scalar localtime $end_time;
    printf $fh $fmt, 'Run Arguments:',    $self->{arguments} if $self->{arguments};
    printf $fh "${hash}\n";

    my $ts = $start_time;
    while (my ($key, $next_ts, $label) = $self->{ts}->next) {
        $label ||= $key;
        printf $fh $fmt, "$label Time:", ($next_ts - $ts) . 's';
        $ts = $next_ts;
    }
    printf $fh $fmt, 'Total Run Time:',   ($end_time - $start_time) . 's';
    print $fh "${hash}\n";

    if (my $gtop_data = $self->{gtop_data}) {
        while (my ($key, $size, $label) = $gtop_data->next) {
            $label ||= $key;
            printf $fh $fmt, 
                "Post $label Memory Usage:", sprintf('%0.1f MB', $size / (1024 * 1024));
        }
        printf $fh $fmt, 
            'Peak Memory Usage:', sprintf('%0.1f MB', $self->{gtop_max} / (1024 * 1024));
        print $fh "${hash}\n";
    } else {
        print $fh "${hash}GTop not installed, memory usage stats disabled\n";
        print $fh "${hash}\n";
    }

    my $data = $self->{data};
    for my $key (sort keys %$data) {
        my $value = $data->{$key}->{value};
        $value .= " $data->{$key}->{units}" if $data->{$key}->{units};
        my $label = $data->{$key}->{label} || $key;
        $label .= ':' if substr($label,-1) ne ':';
        printf $fh $fmt, $label, $value;
    }
    printf $fh "${hash}\n";
}

# Return a hashref of the stats data
sub as_hash {
    my $self = shift;

    $self->end;

    # Reset iterators
    $self->reset;

    my $hash = {
        start_time      => $self->{start_time},
        end_time        => $self->{end_time},
        run_times       => [],
        memory_usage    => [],
        files           => {},
    };
    $hash->{arguments} = $self->{arguments} if $self->{arguments};

    # Run time stats (seconds)
    my $ts = $self->{start_time};
    while (my ($key, $next_ts, $label) = $self->{ts}->next) {
        push @{$hash->{run_times}}, $key => ($next_ts - $ts) . ' s';
        $ts = $next_ts;
    }
    push @{$hash->{run_times}}, "total" => ($self->{end_time} - $self->{start_time}) . ' s';

    # Memory stats(MB)
    if (my $gtop_data = $self->{gtop_data}) {
        while (my ($key, $size, $label) = $gtop_data->next) {
            $size /= (1024 * 1024);
            push @{$hash->{memory_usage}}, "post_$key" => sprintf('%.01f MB', $size);
        }
    }
    push @{$hash->{memory_usage}}, max => sprintf('%.01f MB', $self->{gtop_max} / (1024 * 1024));

    # File stats (hashref, key => value)
    for (keys %{$self->{data}}) {
      $hash->{files}->{$_}  = $self->{data}->{$_}->{value};
      $hash->{files}->{$_} .= " $self->{data}->{$_}->{units}" if $self->{data}->{$_}->{units};
    }

    return $hash;
}

# Record end time
sub end {
    my $self = shift;
    $self->{end_time} ||= time;
}

# Check/record max memory usage
sub check_maxmem {
    my $self = shift;
    return unless $self->{gtop};
    my $mem = $self->{gtop}->proc_mem($$)->size;
    $self->{gtop_max} = $mem if $mem > $self->{gtop_max};
}

# Record current time (and memory, if applicable) against $key in ts dataset
sub timestamp {
    my ($self, $key, $label) = @_;
    # If no label given, assume key is actually label, and derive key
    if (! $label) {
        $label = $key;
        $key = lc $label;
        $key =~ s/\s+/_/g
    }
    $self->{ts}->set($key => time, label => $label);
    return unless $self->{gtop};
    $self->{gtop_data}->set($key => $self->{gtop}->proc_mem($$)->size, label => $label);
    $self->check_maxmem;
}

# Record a datum
sub set {
    my ($self, $key, $value, %arg) = @_;
    $self->{data}->set($key, $value, %arg);
}

# Reset dataset iterators
sub reset {
    my $self = shift;
    $self->{ts}->reset;
    $self->{gtop_data}->reset if $self->{gtop_data};
}

sub note_stored_chunk {
    my ($self, $chunk) = @_;
}

package Brackup::BackupStats::OrderedData;

use Carp;

sub new {
    my $class = shift;
    return bless {
        index  => 0,
        list   => [],       # ordered list of data keys
        data   => {},
        label  => {},
    }, $class;
}

sub set {
    my ($self, $key, $value, %arg) = @_;
    die "data key '$key' exists" if exists $self->{data}->{$key};
    push @{$self->{list}}, $key;
    $self->{data}->{$key}  = $value;
    $self->{label}->{$key} = $arg{label} if $arg{label};
}

# Iterator interface, returning ($key, $value, $label)
sub next {
    my $self = shift;
    return () unless $self->{index} <= $#{$self->{list}};
    my $key = $self->{list}->[$self->{index}++];
    return ($key, $self->{data}->{$key}, $self->{label}->{$key});
}

# Reset/rewind iterator
sub reset {
    my $self = shift;
    $self->{index} = 0;
}

package Brackup::BackupStats::LabelledData;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub set {
    my ($self, $key, $value, %arg) = @_;
    die "data key '$key' exists" if exists $self->{$key};
    $self->{$key}  = { value => $value };
    $self->{$key}->{label} = $arg{label} if $arg{label};
    $self->{$key}->{units} = $arg{units} if $arg{units};
}

1;

# vim:sw=4
