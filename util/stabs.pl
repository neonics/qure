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
!$ARGV[0] and
	die "usage: symtab.pl <kernel.o> <kernel.stabs> [-p] # -p=print\n".
	    "       symtab.pl <kernel.stabs>\n";

!$ARGV[1] and do {
	open BIN, "<:raw", $ARGV[0] or die "Can't open file '$ARGV[0]': $!";
	$size=(stat BIN)[7];
	read BIN, $l, 4;
	print "filesize: $size\n";
	$l=unpack 'l<', $l;
	print "Items: $l\n";
	read BIN, $a, $l*4;
	read BIN, $d, $l*4;

	my @addrs = unpack "L*", $a;
	my @data = unpack "L*", $d;

	$nf=0;
	map { $foo = 1+($_ >> 16); $nf = $nf>$foo?$nf:$foo } @data;
	print "sources: $nf\n";

	read BIN, $s, $nf * 4;
	read BIN, $sn, $size - (1 + 2*$l + $nf) * 4;
	@sni=unpack 'L*', $s;
	@sns=unpack '(Z*)*', $sn;

#	map {print "source: $_: $st{$_}\n" } keys %st;
	#map {print "source: $_\n" } @sns;

	for ($i = 0; $i < scalar(@data); $i++)
	{
		printf "%08x %s:%d\n", $addrs[$i], $sns[$data[$i]>>16],
			$data[$i]&0xffff;

	}
	exit;
};

@c = `objdump -G $ARGV[0]`; chomp @c;

@addresses=();
@lines=();
%sources=();
@data=();
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
		$addr=hex $addr;
		push @addresses, $addr;
		push @lines, $line;
		push @data, int($line) | ($sources{$cur_source}-1) << 16;
		$ARGV[2] eq '-p' and printf "%08x %s:%s\n", $addr, $cur_source, $line;
	}
} @c;


open BIN, ">:raw", $ARGV[1] or die "Cant open file '$ARGV[1]': $!";

print BIN pack "l<", scalar(@addresses);
map { print BIN pack "L<", $_ } @addresses;
map { print BIN pack "L<", $_ } @data;
$o=4 * scalar(@unique_sources);
map { print BIN pack "L<", $o; $o+=1+length $_ } @unique_sources;
map { print BIN pack "Z*", $_} @unique_sources;

close BIN;
