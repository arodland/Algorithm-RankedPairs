#!/usr/bin/perl
use strict;
use warnings;

use Algorithm::RankedPairs;

my @candidates;

my $filename = shift;
open my $fh, '<:crlf', $filename or die $!;
while (<$fh>) {
  last if /^0$/;
}
while (<$fh>) {
  my ($name) = /^\s*"(.*)"/;
  push @candidates, $name;
}
pop @candidates;

my $mam = Algorithm::RankedPairs->new(
  candidates => \@candidates,
);

seek $fh, 0, 0;
my $header = <$fh>;
while (<$fh>) {
  last if /^0$/;
  chomp;
  s/^\([^)]+\)\s*//;
  my ($count, @ballot) = split " ", $_;
  pop @ballot;

  for my $item (@ballot) {
    if ($item eq "-") {
      $item = "skipped";
    } elsif ($item =~ /=/) {
      $item = [ map $candidates[$_ - 1], split /=/, $item ];
    } else {
      $item = $candidates[$item - 1];
    }
  }

#  pop @ballot while @ballot and $ballot[-1] eq "skipped";
  @ballot = grep { $_ ne 'skipped' } @ballot;
  next unless @ballot;
  $mam->vote(\@ballot, $count);
}

my ($result, $ties) = $mam->compute;

print "=== RESULTS ===\n";
for my $ranking (@$result) {
  printf "%3d: %s\n", $ranking->[1], $ranking->[0];
}

if ($ties) {
  print "\nNOTE: There were some ties, re-running with random voter tiebreaking.\n";

  my ($result, $ties) = $mam->compute(1);
  print "=== RESULTS ===\n";
  for my $ranking (@$result) {
    printf "%3d: %s\n", $ranking->[1], $ranking->[0];
  }

  if ($ties) {
    print "\nWARNING: Even that didn't do it! There are some unresolved preferences.\n";
  }
}


