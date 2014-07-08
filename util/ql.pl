#!/usr/bin/perl
# Qemu Log enrichment
my ($PATH) = $0=~/^(.*)\/[^\/]*$/;

@l=`$PATH/../build/symtab.exe build/kernel.sym`;
chomp @l;
%sym=();
map {
	if ( /([0-9a-f]+): [0-9a-f]+ (.*)/ )
	{
#		print "[$1 : ".hex($1)."] [$2]\n";
		$sym{ hex $1 } = $2;
	}
	#else { print "unparsed: $_\n";}
} @l;


while (<>) {
	#print $_;
	#/^-----+/ and print or
	#/^$/ and print $_ or
	#/^Servicing.*/ and print or
	#/^IN:/ and print or
	#/^\s*$/ and print or
	/^0x([0-9a-f]{16}):(.*)/ and &amend($_,$1,$2) or
	#/^check_exception old: 0x[0-9a-f]+ new 0x[0-9a-f]+/ and print or
	#/^\d+:/ and print
	#die "unknown input: $_";
	print
}

sub amend {
	my ($code,$a,$b) = @_;
	chomp $code;
	$a = hex $a;
	$a -= 0x13000;
	printf "AMEND (%08x: %s): %s\n", $a,
		getsym( $a ),
		$code
	;
	return 1;
}

sub getsym {
	my ($addr) = @_;

	@k = sort {$a <=> $b } keys %sym;
	for ( my $i = 0; $i<scalar(@k); $i++)
	{
		if ( $k[$i] > $addr )
		{
			$tmp = $addr - $k[$i-1];
			$tmp = $tmp < 0
				? "-".sprintf("[$tmp]%x",($k[$i] - $addr))
				: "+".sprintf("%x",$tmp);
			return
				sprintf("[%x..%x]", $k[$i-1], $k[$i] ).
				sprintf( "%s%s", $sym{ $k[$i-1] } , $tmp );
		}
	}
	return "[unknown:$addr]";
}
