#!/usr/bin/perl -w
# Copyright 2005-2006 Tomasz Wegrzanowski
# Released under GNU General Public License, version 2 or higher

use Tawbot;

my $movetalk = 1;
my $reason;

my $bot = Tawbot->new(
    "dontmovetalk|T" => sub { $movetalk = 0 },
    "reason|r=s" => sub { $reason = $_[1] },
);

my ($from, $to) = @ARGV;

my $url = $bot->url(
    title  => "Specjalna:Movepage",
    target => $from,
);
my $cnt = $bot->get($url);
my $form = HTML::Form->parse($cnt, $url);

# $form->value("wpMovetalk", $movetalk ? 1 : 0);
$form->value("wpReason", $reason);
#$form->value("wpOldTitle", $from);
$form->value("wpNewTitle", $to);

#print "$_\n" for $form->form;

my $req = $form->click;

my $res = $bot->request($req);
unless($res->is_success)
{
    print STDERR "Can't move [[$from]] to [[$to]]\n";
    exit 1;
}
