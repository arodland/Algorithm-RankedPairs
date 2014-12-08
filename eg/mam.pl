#!/usr/bin/perl
use strict;
use warnings;

use Algorithm::MaximizeAffirmedMajorities;
use Data::Printer;

my ($mam, $result);

$mam = Algorithm::MaximizeAffirmedMajorities->new(
  candidates => [qw/x y z/],
);
$mam->vote([qw/x y z/], 34);
$mam->vote([qw/y x z/], 10);
$mam->vote([qw/y z x/], 10);
$mam->vote([qw/z y x/], 46);

$result = $mam->compute;
&p($result);

$mam = Algorithm::MaximizeAffirmedMajorities->new(
  candidates => [qw/x y z/],
);
$mam->vote([qw/x y z/], 34);
$mam->vote([qw/y x z/], 10);
$mam->vote([qw/y z x/], 10);
$mam->vote([qw/z/], 46);

$result = $mam->compute;
&p($result);

$mam = Algorithm::MaximizeAffirmedMajorities->new(
  candidates => [qw/x y z/],
);
$mam->vote([qw/x y z/], 32);
$mam->vote([qw/y z x/], 34);
$mam->vote([qw/z x y/], 34);

$result = $mam->compute;
&p($result);

$mam = Algorithm::MaximizeAffirmedMajorities->new(
  candidates => [qw/x y z/],
);
$mam->vote([qw/x y z/], 20);
$mam->vote([qw/y z x/], 30);
$mam->vote([qw/z y x/], 40);
$mam->vote([qw/z x y/], 10);

$result = $mam->compute;
&p($result);
