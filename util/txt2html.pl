#!/usr/bin/perl
$ARGV[0] or die "usage : txt2html [-t template] <txtfile> [out.html]";

if ( $ARGV[0] eq '-t' ) {
	shift @ARGV;
	open IN, $_ = shift @ARGV or die "can't open template $_: $!";
	$template = join("", (<IN>) );
	close IN;
}

open IN, $ARGV[0] or die "can't open $ARG[0]: $!";
@l = <IN>;
close IN;

$c = join "", @l;

$c=~ s@<@&lt;@g;
$c=~ s@&@&amp;@g;

$c=~ s@\n*([^\n]+)\n=+\n@\n\n<h1>$1</h1>\n\n@g;
$c=~ s@\n*([^\n]+)\n-+\n@\n\n<h2>$1</h2>\n\n@g;
$c=~ s@\n*(=+([^\n=]+)=+)\n@\n\n<h1>$2</h1>\n\n@g;
$c=~ s@\n*(-+([^\n-]+)-+)\n@\n\n<h2>$2</h2>\n\n@g;
#$c=~ s@\n(\*\s+([^\n]+))\n@\n<h3>$2</h3>\n\n@g;

$c=~ s@(\n\t+[^\n]*)\n+(?=\n\t)@$1\n\t@g;
$c=~ s@\n(\*\s+([^\n]+)\n+((\t[^\n]*\n)+))+@\n<dt>$2</dt>\n<dd>\n$3</dd>\n\n@g;

$c=~ s@''([^']+)''@<code>$1</code>@g;

$c=~ s@((\n\t[^\n]*)+\n)@<pre>$1</pre>\n@g;
$c=~ s@((\n>[^\n]+)+\n)@<pre>$1</pre>\n@g;

$c=~ s@<pre>(.*?)</pre>\n+@'<PRE>'.&esc($1)."</PRE>\n"@ges;


sub esc { $_ = shift @_; s/\n/\r/g; return $_; }

# NOTES: pattern:  /(?=X)/:
#	lookahead:	(?=pat) (?!pat)
#	lookbehind:	(?<=,   (?<!

$TOK="<!---->";

# level 2
# a)
#$c=~ s@\n ([a-z])+\) ([^\n]+)@\n$TOK<li>$2</li>@g;
#$c=~ s@\n(($TOK<li>[^\n]+</li>\n)+)@\n<ol type="a">$1</ol>\n@g;
#$c=~ s@$TOK@@g;
$c=~ s@\n ([a-z])+\) ([^\n]+(\n\t[^\n]*)*)@\n<li>$2</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n((<li>[^\n]+</li>\n)+)@\n<ol type="a">$1</ol>\n@g;
# level 1
#a)
#$c=~ s@\n([a-z])+\) ([^\n]+(\n<ol.*?</ol>)*)@\n$TOK<li>$2</li>@g;
#$c=~ s@(?<!ol>)\n(($TOK<li>[^\n]+</li>\n)+)@\n<ol type="a">$1</ol>\n@g;
#$c=~ s@$TOK@ @g;
#$c=~ s@\n([a-z])+\) ([^\n]+(\n<ol.*?</ol>)*)@\n<li>$2</li>@g;
$c=~ s@\n([a-z])+\) ([^\n]+(\n<[^\n]+>|\n\t[^\n]*)*)@\n<li>$2</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n(<li>[^\n]+</li>)\n+@<ol type="a">$1</ol>\n@g;
#1) foo
#$c=~ s@\n([\d])+\) ([^\n]+\n<([^ >]+)[^>]+>.*?</\3>)@\n$TOK<li>$2</li>@g;
$c=~ s@\n([\d])+\) ([^\n]+(\n<[^\n]+>|\n\t[^\n]*)*)@"\n<li>".&esc($2)."</li>"@ges;
$c=~ s@li>\n<@li><@g;
$c=~ s@\n((<li>[^\n]+</li>)+)@\n<ol type="1">$1</ol>\n@g;

# level 3:
#    * foo
$c=~ s@\n    \* ([^\n]+)@\n<li>$1</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n(<li>[^\n]+</li>)\n@ <ul>$1</ul>\n@g;

# level 2
#  *foo
$c=~ s@\n  \* ([^\n]+)@\n<li>$1</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n(<li>[^\n]+</li>)\n@ <ul>$1</ul>\n@g;

# level 1
#*foo
$c=~ s@\n\* ([^\n]+)@\n<li>$1</li>@g;
$c=~ s@\n((<li>[^\n]+</li>\n)+)@\n<ul>\n$1</ul>\n@g;

# [label|site]
$c=~ s@\[([^\|\]]+)\|([^\]]+)\]@<a href="$2">$1</a>@g;

#
$c=~ s@\[#([^\]]+)\]@<a href="#$1">$1</a>@g;
$c=~ s@\[=([^\]]+)\]@<a name="$1"/>@g;
#


#$c=~ s@\n\n+@\n</p>\n<p>\n@g;
#$c=~ s@\n([^\n]+\n)+<@\n<p>$1</p>\n<@g;


$c=~ s@\n([^<\n]{1,60})\n([^<\n]{70,}\n)@\n$1<br/>\n$2@g;


$c=~ tr/\r/\n/;
done:

@l=	grep {length($_) }
	split (/\n\n+/, $c);
$c = join( "\n", (map { /(<([^>\n]+)>.*?<\/\2>)/ ? "$_\n" : "<p>$_</p>\n" } @l) );

if ( $template )
{
	 $template =~ s/\$\{CONTENT\}/$c/;
	 $c = $template;
}
else {
$c=<<"EOF";
<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
  </head>
  <body>
$c
  </body>
</html>
EOF
}

$ARGV[1] and do {
#-f $ARGV[1] and die "$ARGV[1] exists.";
open OUT, ">", $ARGV[1] or die;
print OUT $c;
close OUT;
}
or print $c;

exit;

done2:
	$c=~ tr/\r/\n/;
	goto done;
done3:
	$c=~ tr/\r/!/;
	goto done;
