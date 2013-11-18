#!/usr/bin/perl
$xml;
$relpath="";
$template = "template.html";
$menuxml = undef;
$title="";
$tagline="Conscious Computing";
@styles;

while ( $ARGV[0] =~ /^-./ )
{
	my $a = shift @ARGV;
	$a eq '-t' and $template = shift @ARGV or
	$a eq '-x' and $xml = shift @ARGV or
	$a eq '-s' and push @styles, shift @ARGV or
	$a eq '-p' and $relpath = shift @ARGV or
	$a eq '--onload' and $onload .= shift @ARGV or
	$a eq '--menuxml' and $menuxml .= shift @ARGV or
	$a eq '--title' and $title .= shift @ARGV or
	$a eq '--tagline' and $tagline .= shift @ARGV or
	die "unknown option: $a";
}

$xml = defined($xml) ? "'$xml'" : "null";

$onload="template( $xml, '$relpath', [".join(",", map{ "'$_'"} @styles)."]"
	.(defined $menuxml ? ", '$menuxml'" : "")
	."); $onload"
unless $onload;

$c=readfile( $template );
$content= defined $ARGV[0] ? readfile( $ARGV[0] ) : "";

$c=~s/\$\{CONTENT\}/$content/ge;
$c=~s/\$\{TOC\}/$toc/ge;
$c=~s/\$\{ONLOAD\}/$onload/ge;
$c=~s/\$\{RP\}/$relpath/ge;
$c=~s/\$\{TITLE\}/$title/ge;
$c=~s/\$\{TAGLINE\}/$tagline/ge;

print $c;

sub readfile {
	open IN, $_[0] or die "can't find template file $_[0]: $!";
	my @c = <IN>;
	close IN;
	join( '', @c);
}
