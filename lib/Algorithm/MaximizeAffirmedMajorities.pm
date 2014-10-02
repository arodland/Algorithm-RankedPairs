package Algorithm::MaximizeAffirmedMajorities;
# ABSTRACT: Fill me in.
# AUTHORITY
# VERSION

use Moo;
use Types::Standard qw(ArrayRef Map Tuple Str Int);

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

has 'blocs' => (
  is => 'ro',
  isa => Map[Str, Map[Str, Int]],
  lazy => 1,
  builder => '_compute_blocs',
  clearer => '_clear_blocs',
);

has 'tiebreak' => (
  is => 'ro',
  isa => Map[Str, Int],
  lazy => 1,
  builder => '_compute_tiebreak',
  clearer => '_clear_tiebreak',
);

sub add_candidate {
  my ($self, $candidate) = @_;
  push @{ $self->candidates }, $candidate;
  $self->_clear_blocs;
  $self->_clear_tiebreak;
}

sub add_candidates {
  my ($self, @candidates) = @_;
  push @{ shift->candidates }, @candidates;
  $self->_clear_blocs;
  $self->_clear_tiebreak;
}

sub vote {
  my ($self, $ballot, $count) = @_;
  push @{ $self->bundles }, [ $count, $ballot ];
  $self->_clear_blocs;
  $self->_clear_tiebreak;
}

sub _compute_blocs {
  my ($self) = @_;
  my %blocs;
  for my $bundle (@{ $self->bundles}) {
    my ($count, $ballot) = @$bundle;
    my %remaining;
    $remaining{$_} = 1 for @{ $self->candidates };

    for my $set (@$ballot) {
      my @candidates = ref($set) eq 'ARRAY' ? @$set : $set;
      delete $remaining{$_} for @candidates;
      for my $candidate (@candidates) {
        for my $loser (keys %remaining) {
          $blocs{$candidate}{$loser} += $count;
        }
      }
    }
  }

  return \%blocs;
}

sub _compute_tiebreak {
  use Carp 'cluck';
  cluck "tiebreak";
  my ($self) = @_;
  my %ret;
  my $i = 1;

  for my $candidate (sort @{ $self->candidates }) {
    $ret{$candidate} = $i++;
  }
  return \%ret;
}

sub compute {
  my $self = shift;
  my $candidates = $self->candidates;
  my $blocs = $self->blocs;

  my @majorities;
  for my $x (@$candidates) {
    for my $y (@$candidates) {
      if (($blocs->{$x}{$y} ||= 0) > ($blocs->{$y}{$x} ||= 0)) {
        push @majorities, [$x, $y];
      }
    }
  }

  my $compare_majority = sub {
    my ($x, $y, $z, $w) = (@$a, @$b);
    ($blocs->{$x}{$y} <=> $blocs->{$z}{$w})
        ||
    ($blocs->{$w}{$z} <=> $blocs->{$y}{$x})
        ||
    ($self->tiebreak->{$w} <=> $self->tiebreak->{$y})
        ||
    ($self->tiebreak->{$x} <=> $self->tiebreak->{$z})
  };

  @majorities = reverse sort $compare_majority @majorities;

  my $affirm;
  my ($dominates, $dominated);

  $affirm = sub {
    my ($winner, $loser, $reason) = @_;
    my $size = $blocs->{$winner}{$loser};
    $reason ||= "$size votes";

    warn "Affirming $winner over $loser ($reason)\n";
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
        warn "Rejecting $winner over $loser ($size votes) because it would create a cycle.\n";
      } else {
        $affirm->($winner, $loser);
      }
    }
  }

  my (%remaining, @ranking);
  $remaining{$_} = 1 for @$candidates;
  while (keys %remaining) {
    my @winners = grep { !$dominated->{$_} || !keys %{$dominated->{$_}} } keys %remaining;
    if (@winners > 1) {
      @winners = sort {
        $self->tiebreak->{$a} <=> $self->tiebreak->{$b}
      } @winners;
    }
    my $selected = $winners[0];
    warn "Selected $selected\n";
    push @ranking, $selected;
    for my $candidate (@$candidates) {
      delete $dominated->{$candidate}{$selected};
    }
    delete $remaining{$selected};
  }
  return \@ranking;
}

1;
