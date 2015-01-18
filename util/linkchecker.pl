#!/usr/bin/perl

-d $ARGV[0] or die "usage: $0 <directory>\n";

$LOGLEVEL = 0;	# set to 1 to print all links; 0: only print errors.

my $d = $ARGV[0];

my @l = `find $d -name \\*.html`;

my $errors;
chomp @l;
map {
	my ($p) = /^(.*?)\/[^\/]+$/ or die;
	open IN, "<", "$_" or do { warn "cannot read $_: $!"; next; };
	my $c = join( '', <IN> );
	close IN;

	my $msg = "";
	while ( $c=~ /<a\s+[^>]*href=(['"])(.*?)\1/ ) {
		$c=$';
		my $l = $2;

		$l=~ /^#/ and 1 or
		$l=~ /^https?:/ and 1 or do {
			$l =~ s/#.*//;
			$msg .= check( $_, $p, $l );
		}
	}

	if ( length ($msg) )
	{
		$errors++;
		print "--- $_  ($p)\n", $msg
	}

} @l;

exit $errors > 0;



sub check
{
	my ($source, $base, $rel) = @_;
	my $f = $base."/".$rel;
	$f =~ s@/[^/.]+/\.\./@/@g;

	return isfile( $f )
	? ( $LOGLEVEL ? "  * $f [1;32m OK [0m\n" : "" )
	: "  * $f [1;31m NOT FOUND [0m\n";
}

sub isfile {
	return 1 if ( $cache{ $_[0] } );
	$cache{ $_[0] } = -f $_[0];
}
