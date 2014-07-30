#!/usr/bin/perl
# Converts the ascii ouput of objdump -G (stabs debug information)
# to a binary format suitable for quick scanning.
#
# The structure generated is:
# long nr_of_lines		the number lines or addresses.
# long addresses[nr_of_lines]	the addresses for which there is line information
# long data[nr_of_lines]	x>>16 = source file index, x&0xffff = line number
# long sfile_ptr[nr_of_sources]	offset to the source file name relative to sfile_ptr
# char stringtable[unknown]	the asciz names of source files.
#
# The number of source files is not stored, but can be determined by
# scanning the data and taking the max of the high word.
# The offsets to the source filenames are relative to the start of the
# source file offset array (unlike symtab.pl, where the string table
# pointer array has the same length as the other arrays).
$COMPRESSION = 0;
$BASE = 0;	# --base; image base: addess will be subtracted
$PRINT = 0;	# -p
while ( $ARGV[0] =~/^-/ ) {
	$ARGV[0] eq '-C' and do {
		$COMPRESSION = 1; shift @ARGV;
	} or
	$ARGV[0] eq '--base' and do {
		shift @ARGV;
		$ARGV[0] or die "--base requires hex number";
		$BASE = hex shift @ARGV;
	} or
	$ARGV[0] eq '-p' and $PRINT = shift @ARGV
	or die "unknown option: $ARGV[0]";

}

!$ARGV[0] and
	die "usage: symtab.pl [-p] [-C] [--base <hex>] <kernel.o> <kernel.stabs>\n".
	    "       symtab.pl <kernel.stabs>\n\n".
	    "options:\n".
	    "\t-p\tprint\n".
	    "\t-C\tcompress output file\n".
	    "\t--base <hex>\tsubtract number from addresses\n".
	    "\n";

!$ARGV[1] and do {
	open BIN, "<:raw", $ARGV[0] or die "Can't open file '$ARGV[0]': $!";
	$size=(stat BIN)[7];
	read BIN, $l, 4;
	print "filesize: $size\n";
	$l=unpack 'l<', $l;

	$COMPRESSION = $l & 0x40000000;
	$l &= ~$COMPRESSION;

	print "Items: $l\n";

	my @addrs;

	my $readsofar= 4;

	if ( $COMPRESSION )
	{
		# read address hashtree
		print "COMPRESSED\n";
		@addrs = uncompress(\$readsofar);
	}
	else
	{
		read BIN, $a, $l*4;	# read raw address list
		$readsofar += $l*4;
		@addrs = unpack "L*", $a;
	}

	printf "data start: %08x   end %08x\n", $readsofar, $readsofar + $l*4;

	read BIN, $d, $l*4;	# read data (src fn idx<<16 | lineno)
	$readsofar += $l*4;
	my @data = unpack "L*", $d;

	print "data size: ", scalar @data, "\n";

	my $nf=0;
	map { $foo = 1+($_ >> 16); $nf = $nf>$foo?$nf:$foo } @data;
	print "sources: $nf\n";

	printf "source file ptr start: %08x\n", $readsofar;

	read BIN, $s, $nf * 4 or die $!;
	$readsofar += $nf * 4;
	printf "source file str start: %08x\n", $readsofar;
	read BIN, $sn, $size - $readsofar or die $!;
	@sni=unpack 'L*', $s;
	@sns=unpack '(Z*)*', $sn;

	map {print "source: $_: $st{$_}\n" } keys %st;
	map {printf "source %x: $sns[$_]\n", $_ } keys @sns;

	for ($i = 0; $i < scalar(@data); $i++)
	{
		printf "%08x [%08x] %s:%d\n", $addrs[$i], $data[$i], $sns[$data[$i]>>16],
			$data[$i]&0xffff;

	}
	exit;
};

$ARGV[2] and die "extraneous arguments: @ARGV -- ", join( " ", splice( @ARGV, -(scalar(@ARGV)- 2) ) );

print "args:\nPRINT: $PRINT\nCOMPRESSION: $COMPRESSION\nBASE: ".sprintf("%x",$BASE)."\nIN: $ARGV[0]\nOUT: $ARGV[1]\n";

@c = `objdump -G $ARGV[0]`; chomp @c;

%sources=();
@unique_sources=();

$cur_source=undef;
map {
	# 15995  SOL    0      0      00017c3f 312    kernel.s
	($sf) = /\d+\s+SOL\s+\d+\s+\d+\s+[0-9a-f]+\s+\d+\s+(\S+)$/ and do {
		$cur_source=$sf;
		grep { $_ eq $sf } @unique_sources or do {
			push @unique_sources, $sf;
			$sources{$sf} = (scalar @unique_sources);
		}
	};

	# 15996  SLINE  0      109    00017c3f 0
	($line, $addr) = /^\d+\s+SLINE\s+\d+\s+(\d+)\s+([0-9a-f]{8})\s+\d+\s*$/ and do {
		$addr = hex $addr;
		$addr -= $BASE;
		if ( defined $addrsrc{ $addr })
		{
			# multiple source lines for single address..
			#warn "Duplicate address, ignoring: $_\n";
		}
		else
		{
		$addrsrc{ $addr } = int($line) | ($sources{$cur_source}-1) << 16
		;$PRINT and printf "%08x %s:%s\n", $addr, $cur_source, $line;
		}
	}
} @c;


open BIN, ">:raw", $ARGV[1] or die "Cant open file '$ARGV[1]': $!";

if ($COMPRESSION)
{
	%addr;
	map {
		$addr{ $_>>16 }{ $_&0xffff }=1;
	}
	sort {$a<=>$b}	# objdump is not sorted!
	keys %addrsrc;

	print BIN pack "L<", scalar(keys %addrsrc)|0x40000000;

	# format: addresses are 0xAAAABBBB
	#
	# .word AAAA_count # 3 at current for kernel.o
	# .word 0, 1, 2
	#
	# .word 'AAAA=0'_count
	# .word[] # values for 0x0000xxxx
	# .word 'AAAA=1'_count
	# .word[] # values for 0x0001xxxx
	# .word 'AAAA=2'_count
	# .word[] # values for 0x0002xxxx

	# write nr of unique high-16-bit addressess
	print BIN pack "S<", scalar keys %addr;
	map {
		print BIN pack "S<", $_;
	} sort {$a<=>$b} keys %addr;

	# write the arrays for the low-16 addresses for each.
	map {
		my %h = %{$addr{$_}};
		print BIN pack "S<", scalar keys %h;
		print BIN pack "S<*", sort {$a<=>$b} keys %h;
	} sort {$a<=>$b} keys %addr;
}
else
{
	# objdump -G doesn't sort by address, so we do that here.
	#print BIN pack "L<", scalar(@addresses);
	#map { print BIN pack "L<", $_ } @addresses;

	$PRINT and
	map {
		printf "%08x %s:%s\n", $_, $addrsrc{$_}>>16, $addrsrc{$_}&0xffff;
	} sort {$a<=>$b} keys %addrsrc;

	print BIN pack "L<", scalar( keys %addrsrc );
	map { print BIN pack "L<", $_ } sort {$a<=>$b} keys %addrsrc;
}
# sort
#map { print BIN pack "L<", $_ } @data;
map { print BIN pack "L<", $addrsrc{$_} } sort {$a<=>$b} keys %addrsrc;

$o=4 * scalar(@unique_sources);
map { print BIN pack "L<", $o; $o+=1+length $_ } @unique_sources;
map { print BIN pack "Z*", $_} @unique_sources;

close BIN;




sub uncompress
{
	my ($readsofarref) = @_;

	# read high-16 count
	my $a;
	read BIN, $a, 2;
	$$readsofarref += 2;
	my $c = unpack "S<", $a;

	# read high-16 array
	read BIN, $a, $c * 2;
	$$readsofarref += $c * 2;
	my @addrhi = unpack "S<*", $a;

	print "ADDR_HI: ", join(', ', @addrhi), "\n";

	my @ret;

	foreach ( keys @addrhi )
	{
		# read count
		read BIN, $a, 2;
		$$readsofarref += 2;
		$c = unpack "S<", $a;

		printf "%04x???? count: $c (0x%08x)\n",
			$addrhi[$_], $c;

		# read array
		read BIN, $a, $c * 2;
		$$readsofarref += $c * 2;
		my @addrlo = unpack "S<*", $a;

		# compact
		my $hi=  $addrhi[$_] << 16;

		push @ret, map { $hi | $_ } @addrlo;
	}

	@ret;


#	print "ADDRESSES:\n"; map { printf "%08x\n", $_} @ret;
}
