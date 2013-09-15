#!/usr/bin/perl
$ARGV[0] or die "usage : txt2html <txtfile> [out.html]";

open IN, $ARGV[0] or die "can't open $ARG[0]: $!";
@l = <IN>;
close IN;

$c = join "", @l;


$c=~ s@([^\n]+)\n=+\n@<h1>$1</h1>\n\n@g;
$c=~ s@([^\n]+)\n-+\n@<h2>$1</h2>\n\n@g;
$c=~ s@(=+([^\n=]+)=+)\n@<h1>$2</h1>\n\n@g;
$c=~ s@(-+([^\n-]+)-+)\n@<h2>$2</h2>\n\n@g;
#$c=~ s@\n(\*\s+([^\n]+))\n@\n<h3>$2</h3>\n\n@g;
$c=~ s@\n(\*\s+([^\n]+)\n+((\t[^\n]+\n)+))+\n@\n<dt>$2</dt><dd>$4</dd>\n\n@g;


$c=~ s@\n\* ([^\n]+)@\n<li>$1</li>\n@g;
#$c=~ s@((<li>[^<]+</li>\n)+)\n@<ul>$1</ul>\n@g;

$c=~ s@((\n\t[^\n]+)+\n)@<pre>$1</pre>\n@g;

#$c=~ s@\n\n+@\n</p>\n<p>\n@g;

$c=~ s@((\n>[^\n]+)+\n)@<pre>$1</pre>\n@g;

$c=~ s@\n([^<\n]{1,60})\n([^<\n]{70,}\n)@$1<br/>\n$2@g;

@l=split (/\n\n+/, $c);
$c = join( "\n", (map { /^<(.*?)>.*?<\/\1>/ ? $_ : "<p>$_</p>\n" } @l) );

$ARGV[1] and do {
#-f $ARGV[1] and die "$ARGV[1] exists.";
open OUT, ">", $ARGV[1] or die;
print OUT $c;
close OUT;
}
or print $c;
