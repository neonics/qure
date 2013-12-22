#!/usr/bin/perl

use FindBin;
use lib $FindBin::Bin;# . '/lib';
use Template;

my $t = Template->new();
defined $ARGV[0] or do {
	print "Usage: $0 [options] [<inputfile>|-]\n\noptions:\n";
	Template::usage(); exit 1 };
@ARGV = $t->args( @ARGV );

print $t->process( $ARGV[0] ? readfile( $ARGV[0] ) : undef );

sub readfile {
	$ARGV[0] eq '-' and return join('', <> );
	open IN, "<", $_[0] or die "can't read $_[0]: $!";
	my @c=<IN>;
	close IN;
	join('', @c);
}
