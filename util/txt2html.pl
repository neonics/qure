#!/usr/bin/perl

use FindBin;
use lib $FindBin::Bin;
use Template;


%OPT = { 'autop' => 1 };

grep { $_ eq '--no-autop' } @ARGV
and do { $OPT{autop} = 0; @ARGV = grep { $_ ne '--no-autop' } @ARGV; 1};

my $t = new Template();
@ARGV = $t->args( @ARGV );

$ARGV[0] or do {
	print "XXUsage : $0 [--no-autop] [options] <txtfile> [out.html]\n"
	."\t--no-autop\tdo not generate <p> tags on multiple newlines.\n"
	."\noptions:\n";
	Template::usage();
	exit;
};

open IN, $ARGV[0] or die "can't open $ARGV[0]: $!";
@l = <IN>;
close IN;

my $c = "\n".join "", @l;

$c=~ s@&@&amp;@g;
$c=~ s@<@&lt;@g;


# Headings
#
# Heading 1
# =========
$c=~ s@\n+([^\n]+)\n=+\n@\n\n<h1>$1</h1>\n\n@g;
# Heading 2
# ---------
$c=~ s@\n+([^\n]+)\n-+\n@\n\n<h2>$1</h2>\n\n@g;
# === Heading N ===
$c=~ s@\n+((=+)([^\n=]+)=*)\n@"\n\n<h".length($2).">$3</h".length($2).">\n\n"@ge;

# strip empty lines from indented text
$c=~ s@(\n\t+[^\n]*)\n+(?=\n\t)@$1\n\t@g;

# definition lists
# - item
#   description
$c=~ s@\n(\-\s+([^\n]+)\n*?((\n(?!\-|\S)[^\n]*)+))@"\n<dt>$2</dt>\n<dd>".&p(&trim($3))."</dd>\n\n"@ge;
$c=~ s@((<dt>.*?</dt>\n<dd>.*?</dd>\n*)+)@<dl>\n$1</dl>\n\n@gs;

# ''code''
$c=~ s@''([^']+)''@'<code>'.&esc(keepspace($1)).'</code>'@ge;
$c=~ s@`([^`]+)`@'<code>'.&esc(keepspace($1)).'</code>'@ge;

labels("pre");

# <tab>Preformatted text
$c=~ s@((\n\t[^\n]*)+\n)@<pre>$1</pre>\n@g;
# > preformatted text
$c=~ s@((\n>[^\n]+)+\n)@<pre>$1</pre>\n@g;
# pre/dd fixup
$c=~ s@<dd>\s*<pre>\s*(.*?)\s*</pre>\s*</dd>@<dd>\n\t$1\n</dd>@gs;

# preserve preformatted text: prevent further substitution
$c=~ s@<pre>(.*?)</pre>\n+@'<pre>'.&esc($1)."</pre>\n"@ges;


sub p { join("\n", map {"<p>$_</p>"} split "\n\n", $_[0] ) }
sub trim { $_=$_[0]; s/^\s+//; s/\s*$//; $_ }
sub keepspace { $_=$_[0]; s/ /&nbsp;/g; $_ }
sub esc { $_ = shift @_; "{{PACK ".(unpack "H*", $_)."}}" }

# NOTES: pattern:  /(?=X)/:
#	lookahead:	(?=pat) (?!pat)
#	lookbehind:	(?<=,   (?<!


# level 2
# a)
# $TOK="<!---->";
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
#$c=~ s@\n(\d+)\) ([^\n]+(\n<[^\n]+>|\n\s+[^\n]*)*)@"\n<li>".&esc($2)."</li>"@ges;
#$c=~ s@\n(\d+)\) ([^\n]+\n((?!<[^\n]+>|\d+\) ).*?\n)*)@"\n<li>".&esc($2)."</li>"@ges;
# WORKS:
# while ($c=~ s@\n(\d+)\) ([^\n]+(\n( +[^\n]*)*)*)@"\n<li>".&esc($2)."</li>\n\n"@ges){}
$c=~ s@\n(\d+)\) ([^\n]+(\n +[^\n]*|\n(?!\d+\) ))*)@"\n<li>".&esc($2)."</li>"@ges;
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
$c=~ s@\n+[-\*] ([^\n]+)@\n<li>$1</li>@g;
$c=~ s@\n((<li>[^\n]+</li>\n)+)@\n<ul>\n$1</ul>\n@g;

labels();

sub labels {
# [label|site]
$c=~ s@(?<!\t)\[([^\|\]]+)\|([^\]]+)\]@<a class="$_[0]" href="$2">$1</a>@g;

# [#label] : anchor ref (same as [label|#label])
$c=~ s@(?<!\t)\[#([^\]]+)\]@<a class="$_[0]" href="#$1">$1</a>@g;
# [=label] : anchor definition
$c=~ s@(?<!\t)\[=([^\]]+)\]@<a class="$_[0]" name="$1"></a>@g;
# [!note]
$c=~ s@(?<!\t)\[!([^\]]+)\]@<div class='note $_[0]'>$1</div>@g;

# [http://....]  (same as [label|site] but without 'label|')
$c=~ s@(?<!\t)\[(https?://.*?)\]@<a href="$1" class="$_[0]">$1</a>@g;

# [type: message]
$c=~ s@(?<!\t)\[(\S+?):\s*(.*?)\]@<span class='n $1 $_[0]'>$1: $2</span>@gs;

shift and return;
# [Foo] ; local txt/html doc ref
# [Foo#anchor] aswell
$c=~ s@(?<!\t)\[([^\]\.#]+)(#[^\]\.]*)?\]@<a href="$1.html$2">$1</a>@g;
}


# preserve hardlines in paragraphs
$c=~ s@\n([^<\n]{1,60})\n([^<\n]{70,}\n)@\n$1<br/>\n$2@g;


# unpack
while ($c =~ s@{{PACK (.*?)}}@pack( "H*", $1)@ge){}

###########

$c=~ tr/\r/\n/;

@l=	grep {length($_) }
	split (/\n\n+/, $c);

#$c = join( "\n", (map { /^(<([^>\n]+)>.*?<\/\2>|<\/?[^\n>]+\/?>|<d[lt]>.*?<\/dd>)$/s ? "$_\n" : "<p>{{{$_}}}</p>\n" } @l) );
#$c = join( "\n", (map { /^<.*?>$/s ? "$_\n" : "<p>{{{$_}}}</p>\n" } @l) );
$c = join( "\n", (map { /^<|>$/s || !$OPT{autop} ? "$_\n" : "<p>$_</p>\n" } @l) );


$ARGV[1] and do {
#-f $ARGV[1] and die "$ARGV[1] exists.";
open OUT, ">", $ARGV[1] or die;
print OUT $t->process( $c );
close OUT;
}
or do {
print $t->process( $c );
};

