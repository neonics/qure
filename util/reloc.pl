#!/usr/bin/perl
getopt(@ARGV) or
	die "usage: reloc.pl [[-C] <kernel.o>] <kernel.reloc>\n\t-C: compress\n";

$VERBOSE = 1;
$ADDR16 = 0;	# set to 0 to clobber 16-bit relocation entries.


@addr32 = ();
@addr16 = ();


# parse the generated file
!$ARGV[1] and do {
	open BIN, "<:raw", $ARGV[0] or die "Can't open file '$ARGV[0]': $!";
	$size=(stat BIN)[7];
	print "filesize: $size\n";

	read BIN, $l, 4;
	$l=unpack 'l<', $l;
	print "Addr16: $l\n";
	read BIN, $a16, $l*2;
	@addr16 = unpack "S*", $a16;
	$VERBOSE and do {
	for ($i = 0; $i < scalar(@addr16); $i++)
	{
		printf "%04x\n", $addr16[$i]

	}
	};

	read BIN, $l, 4;
	$l=unpack 'L<', $l;
	print "L: $l\n";
	my $compressed = $l & 0x40000000;	# 26% original size
	$l &= ~0xc0000000;	# mask out high 2 bits; highest bit reserved.

	if ( $compressed )
	{
		read BIN, $alphabet, 2;
		read BIN, $alphawidth, 1;
		read BIN, $deltawidth, 1;
		$alphabet = unpack "S<", $alphabet;
		$alphawidth = unpack "C", $alphawidth;
		$deltawidth = unpack "C", $deltawidth;
		$VERBOSE and printf "addr32 count: %d alphabet %d width %d delta width %d\n",
			$l, $alphabet, $alphawidth, $deltawidth;

		read BIN, $a, ($alphawidth>>3) * $alphabet or die;
		@alphabet = unpack &wordp($alphawidth).'*', $a;


		%d2i, %i2d, $index=0;	# create lookup table for delta indices
		map { $i2d{$index} = $_; $d2i{$_} = $index++; } @alphabet;#sort {$a<=>$b} keys %count;

		$VERBOSE > 1 and do {
			map { printf "TABLE index %3d -> delta %08x\n", $_, $i2d{$_} }
			sort{$a<=>$b} keys %i2d;
			map { printf "TABLE delta %08x -> index %3d\n", $_, $d2i{$_} }
			sort{$a<=>$b} keys %d2i;
		};


		read BIN, $a, ($deltawidth>>3) * $l;
		@delta = unpack &wordp($deltawidth).'*', $a;

		$a = 0;
		map { printf "idx %3d (%02x) delta %08x addr %08x\n",
			$_, $_, $i2d{$_}, $a+=$i2d{$_}
		} @delta;
	}
	else
	{
		$VERBOSE and print "addr32 count: $l";
		read BIN, $a32, $l*4;
		@addr32 = unpack "L*", $a32;
	}

	$VERBOSE and do {
	for ($i = 0; $i < scalar(@addr32); $i++)
	{
		my $v = $addr32[$i];
		my $d = $v - $lastval;
		$lastval= $v;
		$count{$d} ++;
		printf "addr %08x  delta %08x\n", $v, $d
	}
	};

	exit;
};

@c = `objdump -r $ARGV[0]` or die "can't read object file $ARGV[0]"; chomp @c;

$count=0;
$secname;

map {
	$count++;
	($sn) = /RELOCATION RECORDS FOR \[([^\]]+)\]:/ and do {
		#print "Relocation records for section '$sn'\n";
		$secname = $sn;
	}
	or
	/OFFSET\s+TYPE\s+VALUE/
	or
	/([0-9a-f]+)\s+(16|dir32)\s+(\S+)/ and do {
		# .strtab section: compact pointer array; relocation
		# is straighforward, so don't store all the addresses.
		# (.strtab should be in .data somewhere!)
		# .stab: source table.
		# .text: as -R (fold data in text) results in .data
		# relocations being mentioned in .text.
		# So we (for now) only need to worry about the .text.
		$secname eq '.text' and
		do {
		#print "$secname [$1] [$2] [$3]\n";

		$2 eq '16'
			? push @addr16, hex $1
			: push @addr32, hex $1;
		};
		1
	}
	or /^\s*$/
	or /^\S+:\s+file format/
	or die "invalid line (count=$count): '$_'\n";

} @c;

&write_table( $ARGV[1], $opt{compressed} );


sub log2 { use POSIX qw/ceil/; ceil( log( $_[0] ) / log(2) ); }
sub words { $_[0] <= 8 ?  8  : $_[0] <= 16 ?  16 :  32 }	# word size
sub wordp { $_[0] <= 8 ? 'C' : $_[0] <= 16 ? 'S<' : 'L<' }	# word pack symbol

sub write_table
{
	my ($name, $compressed) = @_;

	$VERBOSE and print "writing ".
		($compressed?"compressed ":"")."relocation table '$name'\n";

	open BIN, ">:raw", $name or die "Cant open file '$name': $!";

	$VERBOSE and print "* addr16 count: ".@addr16.($ADDR16?"":" clobbered")."\n";
	$ADDR16 and do {
		print BIN pack "L<", scalar(@addr16);
		map { print BIN pack "S<", $_ } @addr16;
	} or	print BIN pack "L<", 0;

	print BIN pack "L<", $v= scalar(@addr32) | ($compressed ? 0x40000000 : 0);
	$VERBOSE and printf "* addr32 count: ".@addr32." (%08x)", $v;
	# using 0x4000 0000 since having that many relocations means all 4Gb
	# is relocated (or encrypted if overlap).

	if ( $compressed )
	{
		my %count, $l=0, $m=0, @delta, %bitfreq;
		map {
			$d=$_ - $l; $l=$_; push @delta, $d;	# delta
			$m=$m<$d?$d:$m;				# max
			$count{$d}++; $bitfreq{log2($d)}++;	# delta freq
		} @addr32;


		print BIN pack "S<", $alphabet=scalar keys %count;
		print BIN pack "C", $kw=words(log2($m)); $ks=wordp($kw);
		print BIN pack "C", $dw=words(log2($alphabet)); $ds=wordp($dw);
		print BIN pack "S*", sort {$a<=>$b} keys %count;	# alphabet
		$VERBOSE and do {
			printf " alpha $alphabet width $kw, delta width $dw\n";
			map { printf "delta width frequency: %d: %d\n", $_, $size{$_} }
			sort {$a<=>$b} keys %size;
	#		map { printf "alphabet: %08x\n", $_ } sort {$a<=>$b} keys %count;
		};

		%d2i, %i2d, $index=0;	# create lookup table for delta indices
		map { $i2d{$index} = $_; $d2i{$_} = $index++; } sort {$a<=>$b} keys %count;
		$VERBOSE > 1 and do {
			map { printf "TABLE index %3d -> delta %08x\n", $_, $i2d{$_} }
			sort{$a<=>$b} keys %i2d;
			map { printf "TABLE delta %08x -> index %3d\n", $_, $d2i{$_} }
			sort{$a<=>$b} keys %d2i;

			$addr = 0;
			map { printf "DELTA %08x idx %3d ADDR %08x \n", $_, $d2i{$_}, $addr+=$_ }
			@delta;
		};

		# write delta indices
		map { print BIN pack "$ds", $d2i{$_} } @delta;	# 50% compression
	}
	else
	{
		$VERBOSE and print "\n";
		map { print BIN pack "L<", $_ } @addr32;
	}

	close BIN;
}

sub getopt
{
	$ARGV[0] or return 0;
	$ARGV[0] eq '-C' and do { $opt{compressed} = shift @ARGV } or $ARGV[0];
}
