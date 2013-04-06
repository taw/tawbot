#!/usr/bin/perl -w
# Copyright 2005-2006 Tomasz Wegrzanowski
# Released under GNU General Public License, version 2 or higher

use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Headers;
use HTTP::Cookies;
use LWP;
use HTML::Form;
use Getopt::Long;

my $cookie_jar_fn = "cookie_jar";
my $username;
my $password;
my $domain = "pl.wikipedia.org";

GetOptions("username|u=s" => \$username,
           "domain|d=s" => \$domain,
           "cookiejar|jar|j=s" => \$cookie_jar_fn,
           "<>" => sub {$username = $_[0]});

unless(defined $username) {
    print "Username: ";
    $username = <STDIN>;
    chomp $username;
}
print "Password: ";
$password = <STDIN>;
chomp $password;

print "Trying to log in as $username\n";

my $login_url = "http://$domain/wiki/Special:Userlogin";

# This way one cookie jar can contain cookies for many projects (unfortunately max 1 login / project)
my $cookie_jar = HTTP::Cookies->new(file => $cookie_jar_fn, autosave => 1, ignore_discard => 1);

my $ua = LWP::UserAgent->new;
$ua->agent("Tawbot (public svn release; plwiki)");
$ua->cookie_jar($cookie_jar);

my $res = $ua->request(GET $login_url);

unless($res->is_success) {
    print "Can't get login form: ", $res->message, "\n";
    exit 1;
}
my $form = HTML::Form->parse($res->content, $login_url);

#print "$_\n" for map {$_->name} $form->inputs;

$form->value("wpName", $username);
$form->value("wpPassword", $password);
$form->find_input("wpRemember")->check;

my $res2 = $ua->request($form->click("wpLoginattempt"));

# It is automatically saved now
#$ua->cookie_jar->save($cookie_jar);
