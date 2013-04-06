# Copyright 2005-2006 Tomasz Wegrzanowski
# Released under GNU General Public License, version 2 or higher

package Tawbot;

# Systematically distinguish STDOUT from STDERR

use Carp;
use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Headers;
use HTTP::Cookies;
use LWP;
use HTML::Form;
use URI;
use Getopt::Long;

# This is a global behaviour, so it isn't a nice encapsulation
#$SIG{__WARN__} = sub { Carp::cluck(@_) };

######################################################################
# Class methods                                                      #
######################################################################
sub ns {
    my $bot = shift;
    my $ns = shift; 
    my %ns_tt = (
        'pl' => {"Category" => "Kategoria"},
        'de' => {"Category" => "Kategorie"},
        'en' => {"Category" => "Category"},
    );
    unless(defined $ns_tt{$bot->{lang}}) {
        die "Unknown language $bot->{lang}";
    }
    unless(defined $ns_tt{$bot->{lang}}{$ns}) {
        die "Unknown namespace $ns in language $bot->{lang}";
    }
    return $ns_tt{$bot->{lang}}{$ns};
}

sub linked_to_image
{
    my $bot = shift;
    my $title = shift;
    my $raw = $bot->get_url(title => "Image:$title");
    my @list;
    if ($raw =~ m!<p>Oto strony odwołujące się do tego pliku:</p>\n<ul>(.*?)</ul>!si)
    {
        my $text = $1;
        push @list, $1 while ($text =~ m!title=".*">(.*)</a>!gi);
    }
    return @list;
}

sub get_project_metainfo {
    my $project_id = shift;
    my %projects = (
        'pl'      => ['http://pl.wikipedia.org/w/index.php', 'pl'],
        'pl.wp'   => ['http://pl.wikipedia.org/w/index.php', 'pl'],
        'de'      => ['http://de.wikipedia.org/w/index.php', 'de'],
        'de.wp'   => ['http://de.wikipedia.org/w/index.php', 'de'],
        'en'      => ['http://en.wikipedia.org/w/index.php', 'en'],
        'en.wp'   => ['http://en.wikipedia.org/w/index.php', 'en'],
        'c'       => ['http://commons.wikimedia.org/w/index.php', 'en'],
        'commons' => ['http://commons.wikimedia.org/w/index.php', 'en'],
    );
    my $result = $projects{$project_id};
    unless(defined $result) {
        die "Project $project_id not known"
    }
    return @$result;
}

sub new {
    my ($package, @extra_args) = @_;
    my $ua = LWP::UserAgent->new;
    $ua->agent("Tawbot (public svn release; plwiki)");
    my $self = bless {
        ua => $ua,
        url => "http://pl.wikipedia.org/w/index.php",
        lang => "pl",
        excludens => [],
        exn => sub {
            my ($url, $msg) = @_;
            die("Can't get $url: $msg");
        },
        cache_read => undef,
        cache_write => undef,
    } => $package;
    my $cookie_jar_fn = "cookie_jar";
    # Local $bot
    {
        local $bot = $self;
        my $result = GetOptions(
            "project|p=s" => sub { 
                my ($url, $lang) = get_project_metainfo($_[1]);
                $bot->{url} = $url;
                $bot->{lang} = $lang;
            },
            "url|u=s" => sub { $bot->{url} = $_[1] },
            "lang|l=s" => sub { $bot->{lang} = $_[1] },
            "cookiejar|jar|j=s" => sub { $cookie_jar_fn = $_[1] },
            "excludens|x=s" => sub { push @{$bot->{excludens}}, $_[1] },
            @extra_args
        );
    }
    my $cookie_jar = HTTP::Cookies->new(file => $cookie_jar_fn); # , autosave => 1, ignore_discard => 1 ?
    $ua->cookie_jar($cookie_jar);
    return $self;
}

######################################################################
# Base URL, HTTP, and caching                                        #
######################################################################

# No other method should build URLs objects,
# they should all call this method
sub url {
    my ($bot, @query) = @_;
    my $u = URI->new($bot->{url});
    $u->query_form(@query);
    return $u->as_string;
}

# No other method should call $bot->{ua}->request
sub request
{ # Weird UTF-8 warning
    my ($bot, @request) = @_;
    local $SIG{__WARN__} = sub {};
    $bot->{ua}->request(@request);
}

# Get arbitrary URL
sub get {
    my ($bot, $url, $cache_key) = @_;
    if($bot->{cache_read})
    {
        my $cached = $bot->{cache_read}->($url, $cache_key);
        return $cached if defined $cached;
    }
    # Weird UTF-8 warning
    local $SIG{__WARN__} = sub {};
    my $res = $bot->request(GET $url);
    $bot->{exn}->($url, $res->message) unless $res->is_success;
    my $content = $res->content;
    $bot->{cache_write}->($url, $cache_key, $content) if($bot->{cache_write});

    return $content;
}

# A small helper method for the common case
sub get_url
{
    my $bot = shift;
    my $url = $bot->url(@_);
    return $bot->get($url);
}

# post method
# It's the only method that retries failed attempts for now
sub post
{
    my ($bot,$form) = @_;
    my $req = $form->click("wpSave");
    # 5 attempts
    my @SLEEP = (0, 1, 5, 30);
    for my $n(0..4) {
        my $res = $bot->request($req);
        last if($res->is_success);
        # It's almost as good
        #last if($res->message eq "Moved Temporarily");
        last if($res->code == 302);
        print STDERR "Can't post: ", $res->message, "\n";
        # Sleep some time
        unless($n == 4) {
            print "(retrying)\n";
            sleep $SLEEP[$n];
        }
    }
}

# $cache_key is not used for this cache
sub install_url_cache {
    my ($bot, $cachedir, $force) = @_;
    $bot->{cache_read} = sub {
        my ($url, $cache_key) = @_;
        my $cachefn = $url;
        $cachefn =~ s@([%/])@$1 eq "%" ? "%%" : "%:"@eg;
        $cachefn = "$cachedir/$cachefn";
        
        if(not $force and (-e $cachefn))
        {
            my $cachefh;
            open $cachefh, "<", $cachefn or die "Can't open cache file $cachefn: $!";
            local $/ = undef;
            $cnt = <$cachefh>;
            close $cachefh;
            return $cnt;
        }
    };
    $bot->{cache_write} = sub {
        my ($url, $cache_key, $cnt) = @_;
        my $cachefn = $url;
        $cachefn =~ s@([%/])@$1 eq "%" ? "%%" : "%:"@eg;
        $cachefn = "$cachedir/$cachefn";

        my $cachefh;
        open $cachefh, ">", $cachefn or die "Can't open cache file $cachefn: $!";;
        print {$cachefh} $cnt;
        close $cachefh;
    };
}

sub install_key_cache {
    my ($bot, $cachedir, $force) = @_;
    $bot->{cache_read} = sub {
        my ($url, $cache_key) = @_;
        return unless $cache_key;
        my $cachefn = $cache_key;
        $cachefn =~ s@([%/])@$1 eq "%" ? "%%" : "%:"@eg;
        $cachefn = "$cachedir/$cachefn";
        
        if(not $force and (-e $cachefn))
        {
            my $cachefh;
            open $cachefh, "<", $cachefn or die "Can't open cache file $cachefn: $!";
            local $/ = undef;
            $cnt = <$cachefh>;
            close $cachefh;
            return $cnt;
        }
    };
    $bot->{cache_write} = sub {
        my ($url, $cache_key, $cnt) = @_;
        return unless $cache_key;
        my $cachefn = $cache_key;
        $cachefn =~ s@([%/])@$1 eq "%" ? "%%" : "%:"@eg;
        $cachefn = "$cachedir/$cachefn";

        my $cachefh;
        open $cachefh, ">", $cachefn or die "Can't open cache file $cachefn: $!";;
        print {$cachefh} $cnt;
        close $cachefh;
    };
}

sub install_null_cache {
    my ($bot) = @_;
    $bot->{cache_read} = undef;
    $bot->{cache_write} = undef;
}

######################################################################
# Helper methods for various actions                                 #
######################################################################

sub get_raw {
    my ($bot,$title) = @_;
    local $bot->{exn} = sub {
        my ($url, $msg) = @_;
        die "Can't get $title (raw): $msg";
    };
    return $bot->get_url(title=>$title, action=>"raw");
}

sub get_raw_rev
{
    my ($bot, $title, $revid) = @_;
    local $bot->{exn} = sub {
        my ($url, $msg) = @_;
        die "Can't get $title (rev $revid): $msg"
    };
    return $bot->get_url(
        title  => $title,
        oldid  => $revid,
        action => 'raw'
    );
}

sub get_edit_form {
    my ($bot,$title,@args) = @_;

    local $bot->{exn} = sub {
        my ($url, $msg) = @_;
        die "Can't get $title: $msg";
    };
    my $url = $bot->url(title=>$title, action=>"edit", @args);
    my $res = $bot->request(GET $url);
    my $form;
    {
        local $SIG{__WARN__} = sub {};
        $form = HTML::Form->parse($res->content, $res->base);
    }
    return $form;
}

sub get_prev_revid
{
    my ($bot, $title, $revid) = @_;
    local $bot->{exn} = sub {
        my ($url, $msg) = @_;
        die "Can't get $title (rev $revid/prev): $msg";
    };
    my $cnt = $bot->get_url(
        title  => $title,
        oldid  => $revid,
        direction => 'prev'
    );
#    $cnt =~ m!href="[^"]*action=edit&amp;oldid=(\d+)"! or die "Can't find $dir revision id for $title (rev $revid)";
    
    $cnt =~ m!<a href="/w/index.php\?title=[^"]+&amp;direction=next&amp;oldid=(\d+)".*?>nast!
    or die "Can't find $dir revision id for $title (rev $revid)";
    #'

    return $1;    
}

# Don't use (local install is nice, but)
sub cached_get_url {
    warn "Deprecated method cached_get_url";
    my ($bot,$cachedir,$url,$force) = @_;
    local $bot->{cache_read} = sub {
        my ($url, $cache_key) = @_;
        my $cachefn = $url;
        $cachefn =~ s@([%/])@$1 eq "%" ? "%%" : "%:"@eg;
        $cachefn = "$cachedir/$cachefn";
        
        if(not $force and (-e $cachefn))
        {
            my $cachefh;
            open $cachefh, "<", $cachefn or die "Can't open cache file $cachefn: $!";
            local $/ = undef;
            $cnt = <$cachefh>;
            close $cachefh;
            return $cnt;
        }
    };
    local $bot->{cache_write} = sub {
        my ($url, $cache_key, $cnt) = @_;
        my $cachefn = $url;
        $cachefn =~ s@([%/])@$1 eq "%" ? "%%" : "%:"@eg;
        $cachefn = "$cachedir/$cachefn";

        my $cachefh;
        open $cachefh, ">", $cachefn or die "Can't open cache file $cachefn: $!";;
        print {$cachefh} $cnt;
        close $cachefh;
    };

    return $bot->get($url);
}

######################################################################
# Methods for obtaining information from servers                     #
######################################################################

sub stuff_in_category
{
    my ($bot,$cat) = @_;
    my @articles;
    my @subcategories;
    my $url = $bot->url(title=>"Category:$cat");
    my $counter = 1;

    while(1)
    {
        my $res = $bot->request(GET $url);

        unless($res->is_success) {
            print STDERR "Can't get Category:$cat (page $counter): ", $res->message, "\n";
            next;
        }    
        my $contents = $res->content;
        # Process $contents

        if($contents =~ m!<h2>(?:Podkategorie|Subcategories)</h2>(.*?)<h2>!s)
        {
            my $subcats = $1;
            push @subcategories, ($subcats =~ m!<a class="CategoryTreeLabel[^"]+"\s+href="[^"]+">(.*?)</a>!mg);
        }
        if($contents =~ m!<h2>(?:Artykuły w kategorii|Articles in category).*?(.*?)<div class="printfooter">!s)
        {
            my $articles = $1;
            while($articles =~ m!<li><a.*?>(.*?)</a></li>|<a href=".*?" title="(.*?)"><img src=".*?" width="\d+" height="\d+" alt="" /></a>!mg){
                push @articles, $1 if defined $1;
                push @articles, $2 if defined $2;
            }
        }

        last unless $contents =~ m!<a href="(\S*?) title="[^"]*">(?:następne|next) 200</a>!;
        my $u=$1;
        $u=~s/&amp;/&/;
        $url = URI->new_abs($u, $url)->as_string;
        $counter ++;
    }

    { a => \@articles, s => \@subcategories };
}

sub subcategories_in_category
{
    my ($bot,$cat)=@_;
    my $stuff = $bot->stuff_in_category($cat);
    return @{$stuff->{s}};
}

sub articles_in_category
{
    my ($bot,$cat)=@_;
    my $stuff = $bot->stuff_in_category($cat);
    return @{$stuff->{a}};
}

sub contributions
{
    my ($bot, $user) = @_;
    my @contributions;

    my $ofs = 0;
    $bot->install_url_cache("contribs");
    while(1)
    {
        my $url = $bot->url();
        local $bot->{exn} = sub {
            my ($url, $msg) = @_;
            die "Can't extract content of ${user}'s contributions (offset $ofs)";
        };
        # Force only the first URL - damn, not with the new API
        # my $cnt = $bot->cached_get_url("contribs", $url, ($ofs ? 0 : 1));
        my $cnt = $bot->get_url(title=>'Special:Contributions', target=>$user, offset=>$ofs, limit=>500);
        $cnt =~ m@<!-- start content -->(.*?)<!-- end content -->@s or die "Can't extract content of ${user}'s contributions (offset $ofs)";
        $cnt = $1;

        #while($cnt =~ m@<li>.*?<a.*?>.*?</a>\)\s+<a.*?href=".*?oldid=(\d+)".*?>.*?</a>\s*(?:<span class="minor">(m)</span>)?\s+<a.*?>(.*?)</a>\s*(?:<span class='comment'>\((.*)\)</span>)?@g)
        while($cnt =~ m@<li>.*?
                         \(<a.*?>.*?</a>\)\s+
                         \(<a.*?href=".*?oldid=(\d+)".*?>.*?</a>\)\s+
                         (?:<span class="minor">(m)</span>)?\s+
                         <a.*?>(.*?)</a>\s*
                         (?:<span\s*class='comment'>\((.*?)\)</span>)@gx)
        {
            my $revid   = $1;
            my $minor   = $2 ? 1 : 0;
            my $title   = $3;
            my $comment = $4 || "";
            push @contributions, {
                revid => $revid,
                title => $title,
                summary => $comment,
                minor => $minor
            };
        }

        last unless $cnt =~ m!\(<a href="[^"]*?offset=(\d+)[^"]*?">nast.*? \d+</a>\)!;
        $ofs = $1;
    }
    # It's absolutely horrible to do such a thing
    $bot->install_null_cache();

    return @contributions;
}

# Ignores continue links, get only the first 1000 links
sub what_links_to
{
    my ($bot, $title, $space) = @_;
    my $url = $bot->url(
        title => "Special:Whatlinkshere",
        target=> $title,
        limit => 5000,
        namespace => $space,
        from => 0
    );

    my $res = $bot->request(GET $url);
    unless($res->is_success) {
        print STDERR "Can't get $title: ", $res->message, "\n";
#       print STDERR $res->content, "\n";
        die;
    }
# @  - blah, kate is dumb
    $res->content =~ m@<!-- start content -->(.*)<!-- end content -->@s or return;
    my $cnt = $1;
    $cnt =~ m@<ul>(.*)</ul>@s or return;
    $cnt = $1;
    $cnt =~ s!\s*\(<a href="[^"]+" title="[^"]+">.{1,3} linkuj.{1,2}ce</a>\)!!g;
    my @list = ();
    my @cor = ();
    while (1)
    {
        if ($cnt =~ s!^<li><a href="[^"]+" title="[^"]+">(.*?)</a></li>\s*!!) {
            push @list, [$1, 0, reverse @cor];
        } elsif ($cnt =~ s!^<li><a href="[^"]+" title="[^"]+">(.*)</a> \((?:redirect|strona przekierowuj.{1,2}ca)\)\s*!!) {
            push @list, [$1, 1, reverse @cor];
        } elsif ($cnt =~ s!^<li><a href="[^"]+" title="[^"]+">(.*)</a> \((?:inclusion|do.{2,4}czony szablon)\)\s*!!) {
            push @list, [$1, 2, reverse @cor];
        } elsif ($cnt =~ s!^<ul>\s*!!) {
            push @cor, $list[-1][0];
        } elsif ($cnt =~ s!^</ul>\s*!!) {
            pop @cor;
        } elsif ($cnt =~ s!^</li>\s*!!) {
            # Ignore ;-)
        } elsif ($cnt =~ m!^\s*$!) {
            last;
        } else {
            warn "Can't parse: $cnt";
            last;
        }
    }

    return @list;
}

######################################################################
# Methods that edit text                                             #
######################################################################

sub links_subst
{
    my ($bot, $cnt, $lambda) = @_;

    $cnt =~ s!
    (
        \Q[[\E  ([^\|\]]+?)  \Q]]\E  ([A-Za-z]*)
        |
        \Q[[\E  ([^\|\]]+?) \Q|\E  ([^\]]+?) \Q]]\E
    )
    !
        my $res = (defined $2) ? $lambda->($2, $2.$3) : $lambda->($4, $5);
        (defined $res) ? $res : $1;
    !egx;
    return $cnt;
}

sub link_subst_smart
{
    my ($bot, $cnt, $operation) = @_;
    $bot->links_subst($cnt, sub {
        local ($main::l, $main::d) = @_;
        my ($orig_l, $orig_d) = @_;
        $operation->();
        if (($orig_l ne $main::l) or ($orig_d ne $main::d)) {
            if($main::l eq $main::d or ucfirst($main::l) eq ucfirst($main::d)) {
                return "[[$main::d]]"
            } else {
                return "[[$main::l|$main::d]]"
            }
        } else {
            return;
        }
    });
}

######################################################################
# Methods that post something                                        #
######################################################################

sub kategoria_fix {
    my ($bot,$article_title,$cmd) = @_;
    my @CMD = @$cmd;

    print "Trying $article_title ...";

    my $form = $bot->get_edit_form($article_title);
    my $contents = $form->value("wpTextbox1");

    print "downloaded\n";

    # Is this actually useful ?
    $contents =~ s@&lt;@<@g;
    $contents =~ s@&gt;@>@g;
    $contents =~ s@&quot;@\"@g;
    $contents =~ s@&amp;@&@g;

    # Find a sort key
    my @sort_key_in = $contents =~ m!\[\[(?:Category|Kategoria):(.*?)\]\]!ig;
    my %Sort_key;
    for(@sort_key_in) {
        if(/\|(.*)/) {
            $Sort_key{$1} = 1;
        } else {
            $Sort_key{""} = 1;
        }
    }
    my @sort_key_list = keys %Sort_key;
    my $the_sort_key = "";
    if (@sort_key_list == 0) {
    } elsif (@sort_key_list == 1) {
        $the_sort_key = "|" . $sort_key_list[0] unless $sort_key_list[0] eq "";
    } else {
        print "Multiple sort keys present (", (join ", ", map {"`$_'"} @sort_key_list), "), ignoring all\n";
    }

    # Local vars instead of $env
    local $cnt = $contents;
    local $sortkey = $the_sort_key;
    local $ok = 0;
    local $try = 0;
    local @summary = ();
    local @failmsg = ();
    local $title = $article_title;
    # We assume that @failmsg + $ok == $try
    
    for(@CMD)
    {
        $_->();
    }

    my $summary = join(" ", @summary);
    my $failmsg = join("; ", @failmsg);

    if($ok == 0) {
        print "\tTotal failure: $failmsg\n";
        return;
    } elsif($ok != $try) {
        print "\tOnly $ok of $try changes: $failmsg\n";
    } else {
        print "\tAll $ok changes to commit.\n"
    }

    $form->value("wpTextbox1", $cnt);
    $form->value("wpSummary", $summary);
    
    $bot->post($form);
}

# pre-compile @CMD for kategoria_fix
sub compile_cmd
{
    my $bot = shift;
    my @CMD;
    for(@_)
    {
        if (/^-(.*)/) {
            my $x = $1;
            my $s = $1;
            $x =~ s/[ _]/[ _]/g;
            $s =~ s/[ _]/ /g;
            my $k_rx = qr/\[\[(?:Kategoria|Category)\s*:\s*$x(?:\s*\|.*?)?]\]/i;

            my $cmd = sub {
                $try ++;
                if ($cnt =~ s@$k_rx@@) {
                    $ok ++;
                    push @summary, "-$s";
                } else {
                    push @failmsg, "not in $s";
                }
            };
            push @CMD, $cmd;
        } elsif (/^Q(.*)/) {
            my $k = $1;
            my $rx = qr!\[\[(?:Kategoria|Category):$k\|(.*?)\]\]!i;
            
            my $cmd = sub {
                $try ++;
                if ($cnt =~ m@$rx@) {
                    $ok ++;
                    $sortkey = "|$1";
                    print "New sort key - |$1\n";
                } else {
                    push @failmsg, "Sort key for category $k not present";
                }
            };
            push @CMD, $cmd;
        } elsif (/^\+(.*)/) {
            my $k = $1;
            my $s = $1;
            $k =~ s/[ _]/[ _]/g;
            $s =~ s/[ _]/ /g;
            my $k_rx = qr/\[\[(?:Kategoria|Category)\s*:\s*$k(?:\s*\|.*?)?\]\]/i;

            my $cmd = sub {
                my $k_txt = "[[".$bot->ns("Category").":$s".$sortkey . "]]";
                
                $try ++;
                if ($cnt =~ m@$k_rx@) {
                    push @failmsg, "already in $s";
                } else {
                    $ok ++;
                    $cnt .= $k_txt;
                    push @summary, "+$s";
                }
            };
            push @CMD, $cmd;
        } elsif (/^x<(.*)><(.*)>/) {
            # change category from $1 to $2
            my $s1 = $k1 = $1;
            my $s2 = $k2 = $2;
            $k1 =~ s/[ _]/[ _]/g;
            $s1 =~ s/[ _]/ /g;
            $s2 =~ s/[ _]/ /g;
            my $k_rx = qr/\[\[(Kategoria|Category)\s*:\s*$k1\s*(\|.*?)?\]\]/i;

            my $cmd = sub {
                $try ++;
                if ($cnt =~ s@$k_rx@\[\[$1:$k2$2\]\]@) {
                    $ok ++;
                    push @summary, "${s1}-->${s2}";
                } else {
                    push @failmsg, "not in $s1";
                }
            };
            push @CMD, $cmd;
        } elsif (/^!(.*)/) {
            my $k = $1;
            my $s = $1;
            $k =~ s/[ _]/[ _]/g;
            $s =~ s/[ _]/ /g;
            my $k_rx = qr/\[\[(?:Kategoria|Category)\s*:\s*$k(?:\s*\|.*?)?\]\]/i;
            
            my $cmd = sub {
                my $k_txt = "[[".$bot->ns("Category").":${s}${sortkey}]]";
                
                $try ++;
                if ($cnt =~ s@$k_rx@$k_txt@) {
#                            print "$title sort key corrected\n";
                    $ok ++;
                    push @summary, "$s (poprawa klucza sortowania)";
                } else {
                    push @failmsg, "not in $s";
                }
            };
            push @CMD, $cmd;
        } elsif (/^S(.*)$/) {
            my $sk = $1;
            $sk = "|$sk" unless $sk eq "";
        
            my $cmd = sub {
                $sortkey = $sk;
            };
            push @CMD, $cmd;
        } elsif (/^{(.*)}$/s) {
            my $code = $1;
        
            my $cmd = sub {
                $try++;
                my $res = eval $code;
                $ok++ if $res;
            };
            push @CMD, $cmd;
        } elsif (/^L<(.*)><(.*)>$/) {
            my ($from,$to) = ($1,$2); # $from is rx or string ?
            my $from_rx = qr@\Q[[\E$from(\Q|\E|\Q]]\E)@;

            my $cmd = sub {
                $try ++;

                my $ccount = $cnt =~ s/\[\[$from(\||\]\])/[[$to$1/g;
                if ($ccount) {
                    $ok ++;
                    my $razy = $ccount == 1 ? "raz" : "razy";
                    push @summary, "[[$from]] -> [[$to]] ($ccount $razy)";
                } else {
                    push @failmsg, "no links to $from";
                }
            };

            push @CMD, $cmd;
        } else {
            die "Unknown operation: $_"
        }
    }
    return @CMD;
}

sub run
{
    my $bot = shift;
    my $program = shift;
    my @CMD = $bot->compile_cmd(@$program);
    $|=1;
    for(@_)
    {
        chomp;
        next unless m@\S@;
        my $p = $_;
#        $p =~ s/([\200-\377])/sprintf "%%%02x", ord($1)/ge;
        $p =~ s/_/ /g;
    
        $bot->kategoria_fix($p,\@CMD);
    }
}

sub stdin_iface
{
    my $bot = shift;
    my @CMD = $bot->compile_cmd(@_);
    $|=1;
    while(<STDIN>)
    {
        chomp;
        next unless m@\S@;
        my $p = $_;
#        $p =~ s/([\200-\377])/sprintf "%%%02x", ord($1)/ge;
        $p =~ s/_/ /g;

        $bot->kategoria_fix($p,\@CMD);
    }
}

sub refresh
{
    my $bot = shift;
    for my $title(@_)
    {
        print "Trying $title ...";

        my $form = $bot->get_edit_form($title);
        print " downloaded ...";
        
        $form->value("wpSummary", "refresh");

        $bot->post($form);
        print " refreshed.\n";
    }
}


# Does not fix _/space and ucfirst
# Return 0 if prefix matches an exclude rule
sub edit_ok
{
    my ($bot, $title) = @_;
    for my $x(@{$bot->{excludens}})
    {
        return 0 if $x eq substr $title, 0, length($x);
    }
    return 1;
}

sub fill_form
{
    my ($bot, $form, $text, $summary) = @_;
    $form->value("wpTextbox1", $text);
    $form->value("wpSummary", $summary);
    return;
}

sub relink {
    my ($bot,$title,$operation,$gen_summary) = @_;

    print "Trying $title ... ";
    my $form = $bot->get_edit_form($title);
    print "downloaded.\n";

    my $cnt = $form->value("wpTextbox1");
    my $new_cnt = $bot->links_subst($cnt, sub {
            local ($main::l, $main::d) = @_;
            my ($orig_l, $orig_d) = @_;
            $operation->();
            if (($orig_l ne $main::l) or ($orig_d ne $main::d)) {
                if($main::l eq $main::d or ucfirst($main::l) eq ucfirst($main::d)) {
                    return "[[$main::d]]"
                } else {
                    return "[[$main::l|$main::d]]"
                }
            } else {
                return;
            }
        });
    if($cnt ne $new_cnt) {
        my $summary = $gen_summary ? ($gen_summary->()) : "linki poprawione";
        $form->value("wpSummary", $summary);
        $form->value("wpTextbox1", $new_cnt);
        $bot->post($form);
        print "* done.\n";
    } else {
        print "* done (no changes).\n";
    }
}

######################################################################
# Methods that perform some other action                             #
######################################################################

sub upload {
    my $bot = shift;
    my $file = shift;
    my %args = @_;

    my $license = (defined $args{license}) ? $args{license} : "self|GFDL|cc-by-sa-2.5,2.0,1.0";
    my $summary = $args{summary};
    my $watchthis = $args{watchthis} ? "true" : undef;
    my $destfilename = $args{destfilename};

    unless (defined $destfilename)
    {
        $destfilename = $file;
        $destfilename =~ s!^.*/!!; # Remove everything up to last /
    }

    print "Uploading $file ... ";

    my $url = $bot->url(title  => "Special:Upload");
    my $cnt = $bot->get($url);
    
    my $form = HTML::Form->parse($cnt, $url);

    $form->value("wpUploadFile", $file);
    $form->value("wpDestFile", $destfilename);
    $form->value("wpUploadDescription", $summary);
    $form->value("wpWatchthis", $watchthis ? 'true' : undef);
    $form->value("wpLicense", $license);

    my $req = $form->click;

    my $res = $bot->request($req);

#    if ($res->is_success)
#    {
# Change to $bot->{exn}->(); ?
#      print ": ", $res->message, "\n";
#        exit 1;
#    }
    if ($res->code == 302)
    {
           print "uploaded ... \n";
           return 1;
    }
    else
    {
           print "something went wrong\n";
    }
}

         
sub get_all_pages {
    my ($bot, $ns) = @_;
    my @pages;
    my $from = "";
    while(1) {
        my $page = $bot->get_url(
            title     => "Special:Allpages",
            from      => $from,
            namespace => $ns,
        );
        push @pages, ($page =~ m!<td><a href=".*?" title=".*?">(.*?)</a></td>!g);

        if ($page =~ m!<a href="\Q/w/index.php?title=Specjalna:Allpages&amp;from=\E(.*?)\Q&amp;namespace=\E\d+" title="Specjalna:Allpages">Następna strona!) {
            $from = $1;
            # Get rid of %XX
            $from =~ s!%(..)!sprintf "%c", hex($1)!ge;
            next;
        }
        last;
    }
    return @pages;
}

sub get_list_of_editors {
    my ($bot, $title) = @_;
    my $cnt = $bot->get_url(title=>$title, action=>"history");
    $cnt =~ m@<input class="historysubmit".*?>(.*?)</form>@s or die "Cannot parse: $cnt";
    $cnt = $1;
    my @editors;
    
    while ($cnt =~ m@^<li>(.*?)</li>@gm) {
        my $history_entry = $1;

        die "Cannot parse history entry: $history_entry"
            unless $history_entry =~ m@<span class='history-user'><a href="[^"]*"(?: class="new")? title="[^"]*">(.*?)</a>@;
        my ($editor) = ($1);
        push @editors, $editor;
    }
    return @editors;
    
}

sub linked_to_image
{
    my ($bot, $title) = @_;
    my $raw = $bot->get_url(title => "image:$title");
    my @list;
    if ($raw =~ m!<p>Oto strony odwołujące się do tego pliku:</p>\n<ul>(.*?)</ul>!si)
    {
	my $text = $1;
        push @list, $1 while ($text =~ m!title=".*">(.*)</a>!gi);
    }
    return @list;
}

sub get_rev_ids
{
    my ($bot, $title, $number) = @_;
    my $raw = $bot->get_url(title => $title, action => "history", limit => $number);
    my @list;
#    print $raw;
    while ($raw =~ m!<a href="/w/index\.php\?title=(.+)&amp;oldid=(\d+)".*?<span class=.history-user.>.*?<a href=".*" title=".*">(.*?)</a></span>.*<span (class=.comment.>(.+)</span>|(.+?)</li>)!gi)
    {
	push @list, [$2, $3, $5];
    }
    return @list;
}

1;
