package Algorithm::RankedPairs;
# ABSTRACT: Tideman Ranked Pairs
# AUTHORITY
# VERSION

use Moo;
use Types::Standard qw(ArrayRef Map Tuple Str Int);
use List::Util 'shuffle';
use Storable 'dclone';
use Log::Contextual qw(:log set_logger);
use Log::Dispatch;

my $log = Log::Dispatch->new(
  outputs => [
    [ 'File', min_level => 'debug', filename => 'rankedpairs.log' ],
    [ 'Screen' => min_level => 'warning' ]
  ]
);

set_logger $log;

has 'candidates' => (
  is => 'rw',
  isa => ArrayRef[Str],
  default => sub { [] },
);

has 'bundles' => (
  is => 'rw',
  isa => ArrayRef[Tuple[ Int, ArrayRef[Str] ]],
  default => sub { [] },
);

sub add_candidate {
  my ($self, $candidate) = @_;
  push @{ $self->candidates }, $candidate;
}

sub add_candidates {
  my ($self, @candidates) = @_;
  push @{ shift->candidates }, @candidates;
}

sub vote {
  my ($self, $ballot, $count) = @_;
  push @{ $self->bundles }, [ $count, $ballot ];
}

sub _ballot_to_preferences {
  my ($self, $ballot) = @_;
  my @ret;
  my %remaining;
  $remaining{$_} = 1 for @{ $self->candidates };

  for my $set (@$ballot) {
    my @candidates = ref($set) eq 'ARRAY' ? @$set : $set;
    delete $remaining{$_} for @candidates;
    for my $candidate (@candidates) {
      for my $loser (keys %remaining) {
        push @ret, [ $candidate, $loser ];
      }
    }
  }

  return @ret;
}


sub _compute_blocs {
  my ($self) = @_;
  my %blocs;
  for my $bundle (@{ $self->bundles}) {
    my ($count, $ballot) = @$bundle;
    my @preferences = $self->_ballot_to_preferences($ballot);
    for my $preference (@preferences) {
      my ($winner, $loser) = @$preference;
      $blocs{$winner}{$loser} += $count;
    }
  }

  return \%blocs;
}

sub _shuffled_ballots {
  my ($self) = @_;
  my @ballots = map {
    ($_->[1]) x $_->[0]
  } @{ $self->bundles };
  @ballots = shuffle @ballots;
  return @ballots;
}

sub _compute_tiebreak {
  my ($self, $break_ties) = @_;
  my $candidates = $self->candidates;
  my (%exclude, %ret);
  my $dominates = {};
  my $done;

  if (!$break_ties) {
    return +{
      map { ($_ => 0 ) } @$candidates
    };
  }

  BALLOT: for my $ballot ($self->_shuffled_ballots) {
    my @preferences = $self->_ballot_to_preferences($ballot);
    PREFERENCE: for my $preference (@preferences) {
      my ($winner, $loser) = @$preference;
      next if $dominates->{$winner}{$loser} || $dominates->{$loser}{$winner};

      my $temp = dclone($dominates);
      my @work = ($preference);

      while (@work) {
        my ($w, $l) = @{ shift @work };
        next if $temp->{$w}{$l};
        if ($w eq $l) {
          log_debug { "Not adding $winner > $loser to RVH because it would create a cycle.\n" };
          next PREFERENCE;
        }
        $temp->{$w}{$l} = 1;
        for my $candidate (@$candidates) {
          if ($temp->{$l}{$candidate}) {
            push @work, [$w, $candidate];
          }
          if ($temp->{$candidate}{$w}) {
            push @work, [$candidate, $l];
          }
        }
      }
      # Added without creating a cycle, commit.
      log_debug { "Adding $winner > $loser to RVH.\n" };
      $dominates = $temp;
      $done = 1;
      for my $c1 (@$candidates) {
        for my $c2 (@$candidates) {
          unless ($c1 eq $c2 || $dominates->{$c1}{$c2} || $dominates->{$c2}{$c1}) {
            $done = 0;
            next PREFERENCE;
          }
        }
      }
      last PREFERENCE if $done;
    }
    last BALLOT if $done;
  }

  if (!$done) {
    log_warn { "WARNING: ran out of ballots without resolving some RVH preference.\n" };
  }

  my $dominated;
  for my $winner (keys %$dominates) {
    for my $loser (keys %{ $dominates->{$winner}}) {
      $dominated->{$loser}{$winner} = 1 if $dominates->{$winner}{$loser};
    }
  }

  my %remaining;
  $remaining{$_} = 1 for @$candidates;
  my $i = 0;
  while (keys %remaining) {
    my @top = grep { !$dominated->{$_} || !keys %{ $dominated->{$_} } } keys %remaining;
    # Unless we ran out of ballots, @top only has one item. If we *did* run out of ballots,
    # there's a fundamental tie, so give them all the same rank.
    $i++;
    for my $selected (@top) {
      $ret{$selected} = $i;
      for my $candidate (@$candidates) {
        delete $dominated->{$candidate}{$selected};
      }
      delete $remaining{$selected};
    }
  }
  return \%ret;
}

sub compute {
  my $self = shift;
  my $break_ties = 0;

  my $candidates = $self->candidates;
  my $blocs = $self->_compute_blocs;

  my @majorities;
  for my $x (@$candidates) {
    for my $y (@$candidates) {
      if (($blocs->{$x}{$y} ||= 0) > ($blocs->{$y}{$x} ||= 0)) {
        push @majorities, [$x, $y];
      }
    }
  }

  my $tb;
  my $tiebreak = sub {
    return $tb ||= $self->_compute_tiebreak($break_ties);
  };

  my $compare_majority = sub {
    my ($x, $y, $z, $w) = (@$a, @$b);
    return
      ($blocs->{$x}{$y} <=> $blocs->{$z}{$w})
          ||
      ($blocs->{$w}{$z} <=> $blocs->{$y}{$x})
          ||
      ($tiebreak->()->{$w} <=> $tiebreak->()->{$y})
          ||
      ($tiebreak->()->{$x} <=> $tiebreak->()->{$z});
  };

  @majorities = reverse sort $compare_majority @majorities;

  my $affirm;
  my ($dominates, $dominated);

  $affirm = sub {
    my ($winner, $loser, $reason) = @_;
    my $size = $blocs->{$winner}{$loser};
    $reason ||= "$size votes";

    log_debug { "Affirming $winner over $loser ($reason).\n" };
    $dominates->{$winner}{$loser} = 1;
    $dominated->{$loser}{$winner} = 1;

    for my $candidate (@$candidates) {
      # Anyone who dominates the winner also dominates the loser.
      if ($dominates->{$candidate}{$winner} and !$dominates->{$candidate}{$loser}) {
        $affirm->($candidate, $loser, "$candidate -> $winner -> $loser");
      }
      # Anyone dominated by the loser is also dominated by the winner.
      if ($dominates->{$loser}{$candidate} and !$dominates->{$winner}{$candidate}) {
        $affirm->($winner, $candidate, "$winner -> $loser -> $candidate");
      }
    }
  };

  for my $majority (@majorities) {
    my ($winner, $loser) = @$majority;
    my $size = $blocs->{$winner}{$loser};

    unless ($dominates->{$winner}{$loser}) { # Don't re-affirm what we already know
      if ($dominates->{$loser}{$winner}) {
        log_debug { "Rejecting $winner over $loser ($size votes) because it would create a cycle.\n" };
      } else {
        $affirm->($winner, $loser);
      }
    }
  }

  my (%remaining, @ranking);
  $remaining{$_} = 1 for @$candidates;

  my $prev;
  my $i = 0;
  my $j;

  while (keys %remaining) {
    my @winners = grep { !$dominated->{$_} || !keys %{$dominated->{$_}} } keys %remaining;
    if (@winners > 1) {
      @winners = sort {
        $tiebreak->()->{$a} <=> $tiebreak->()->{$b}
      } @winners;
    }

    for my $selected (@winners) {
      $i++;
      $j = $i if !defined $prev or ($break_ties and !defined $tb or $tb->{$selected} != $tb->{$prev});
      log_debug { "Selected $selected\n" };

      push @ranking, [$selected, $j];

      for my $candidate (@$candidates) {
        delete $dominated->{$candidate}{$selected};
      }
      delete $remaining{$selected};
      $prev = $selected;
    }
  }
  return \@ranking;
}

1;
