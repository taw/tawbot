Copyright 2005-2006 Tomasz Wegrzanowski
Released under GNU General Public License, version 2 or higher

----

Tawbot is the code I use mostly to manage categories on plwiki.

Warning: a lot of code uses regular expressions that assume the
         interface is in Polish and also the structure of wiki (namespaces etc.).
	 While local messages are in English, most of the summaries
	 etc. given by the bot are in Polish too.
	 
	 While it would be simple to make it more i18n-friendly,
	 it has not been done yet, because I don't run it
	 on projects in other languages, and all other users
	 I know about also use it on Polish projects.
	 
	 Consider contributing.

Because Perl is so easy to program (I actually use commands
like "write Foo in summary field, click on Submit"), there was
never an occasion for a major code base to develop.

Tawbot.pm module contains almost all the important functions,
the rest is just a bunch of command line scripts.

Technical note on command line options:
    Because tawbot uses Getopt to parse options like -j cookie_jar
    (path to cookie jar file), you can't simply pass -X +Y options
    to stdin_iface, you must prepend them with "--" option

=== Interface ===

Some commands accept arguments on command line, others as separate lines from stdin.
Usually those supposed to be used on just a single page accept cmdline args,
those supposed to be used for mass-changes accept stdin args.

=== Command line arguments ===

Most commands accept the following options:
-j cookie_jar		A jar to get a cookie from (in case of login script it's
                        a name of jar to write to)
			Default cookie_jar for admin commands is ./cookie_jar_admin
			Default cookie_jar for everything else is ./cookie_jar
-x prefix		Don't automatically edit pages with this prefix,
		        useful if you don't want to accidentally leave people messages etc.
-u url			Base URL

=== Typical usage ===

# Bans user - use a cookie jar containing your admin cookie,
# not bot cookie
$ ./ban_user -j cookie_jar_admin -r "April's sockpuppet" -t "3 months" -u "May"

# Clean sortkey of all articles in category Foo (if article is listed under
# some other categories, it doesn't touch sort keys for those categories)
$ ./category_clean_sortkey Foo

# Move all articles from one category to another (currently
  does not move subcategories, just a not-implemented-yet thing).
  They copy&pastes the text from the former category to the latter
  (should it use move feature?), and posts speedy deletion note
  on the former.
  Good for renaming categories.
$ ./category_rename 'Porn movies' 'Adult movies'

# Just move all articles from one category to another.
  Good for merging categories.
$ ./category_rename 'Pornography' 'Adult movies' nomove

# Change all links to redirects to X to link to X directly,
# without affecting the displayed text.
# For example it changes [[Porn]] to [[Pornography|Porn]]
# or [[Macedonian]]s to [[Citizen of FYROM|Macedonians]]
# (assuming the [[Porn]] redirects to [[Pornography]] and
# [[Macedonian]] to [[Citizen of FYROM]]
$ echo "Pornography" | ./fix_links_to_redirects

# Generates a readable report from contribs listing, all fixed links to redirect
$ ./genreport <contribs >report

# Print markup of article Foo to stdout
$ ./get 'Foo'

# List all links to given article (and redirects, and links to redirects etc.)
# ./linked 'Foo'

# Log in, password on stdin (terminal is NOT put in password mode)
$ ./login -u Tawbot -d pl.wiktionary.org -j cookie_jar_wiktionary <password

# Get source for a lot of articles, don't download if the file already exists
$ cat big_list_of_articles ./massget -d output_dir

# Get source for a lot of articles, download even if the file already exists
$ cat big_list_of_articles ./massget -d output_dir --force

# Move a page
$ ./move -r 'Reason' 'Foo' 'Bar'

# Move a page, but not its talk page
$ ./move -T -r 'Reason' 'Foo' 'Bar'

# List all pages in category 'Foo'
$ ./pages_in_category 'Foo'

# Post some completely new content
$ cat /dev/urandom | ./post 'Foo' 'This is something interesting'

# Delete some articles
$ ./delete -j cookie_jar_admin -r "We hate Pokemon" Pikachu Raichu Meow

# Lists all articles in category and its subcategories
  (recursively). Good for generating related changes
  sets for portals.
$ ./recursive_category_finder Fantastyka >fantastyka.txt

# Mark a redirect as temporary
$ echo "Foo" | ./redir_mktemp

# Refresh an article (after categories/links included by templates changed)
$ echo "Foo" | ./refresh

# Run some code over links in Foo
# $l - link target
# $d - link description
# Code should return true if it changed something
# For example the following changes all [[Windows|Windows XP]] to [[Microsoft Windows XP]]
$ echo "Foo" | ./relink -- '{ if ($l eq "Windows" and $d eq "Windows XP") { $l=$d="Microsoft Windows XP"; 1 } else { 0 } }'

# Move 2 articles from one category to another
# (stdin_iface has many more options)
$ ./stdin_iface -- '-Italian cities and villages' '+Italian cities'
Roma
Milano
^D

# List all subcategories of category 'Foo'
$ ./subcategories_in_category 'Foo'

# Upload (to Commons, + add to watchlist, under self2+GFLD+cc-by-sa-2.5,2.0,1.0)
$ ./upload -u 'http://commons.wikimedia.org/w/index.php' -j cookie_jar_commons /path/to/image -d remote_image_name -w -s 'Description'
