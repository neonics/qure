#!/usr/bin/perl

$xml;
$relpath="";
$template = "template.html";
@styles;

while ( $ARGV[0] =~ /^-/ )
{
	my $a = shift @ARGV;
	$a eq '-t' and $template = shift @ARGV or
	$a eq '-x' and $xml = shift @ARGV or
	$a eq '-s' and push @styles, shift @ARGV or
	$a eq '-p' and $relpath = shift @ARGV or
	$a eq '--onload' and $onload .= shift @ARGV or
	die "unknown option: $a";
}

$xml = defined($xml) ? "'$xml'" : "null";

$onload="template( $xml, '$relpath', [".join(",", map{ "'$_'"} @styles)."]); $onload";

$c=readfile( $template );
$content= defined $ARGV[0] ? readfile( $ARGV[0] ) : "";

$c=~s/\$\{CONTENT\}/$content/ge;
$c=~s/\$\{ONLOAD\}/$onload/ge;
$c=~s/\$\{RP\}/$relpath/ge;

print $c;

sub readfile {
	open IN, $_[0] or die "can't find template file $_[0]: $!";
	my @c = <IN>;
	close IN;
	join( '', @c);
}
