#!/usr/bin/perl
!$ARGV[0] and
	die "usage: reloc.pl <kernel.o> <kernel.reloc>\n";

# parse the generated file
!$ARGV[1] and do {
	open BIN, "<:raw", $ARGV[0] or die "Can't open file '$ARGV[0]': $!";
	$size=(stat BIN)[7];
	print "filesize: $size\n";

	read BIN, $l, 4;
	$l=unpack 'l<', $l;
	print "Addr16: $l\n";
	read BIN, $a16, $l*2;
	my @addr16 = unpack "S*", $a16;
	for ($i = 0; $i < scalar(@addr16); $i++)
	{
		printf "%04x\n", $addr16[$i]

	}

	read BIN, $l, 4;
	$l=unpack 'l<', $l;
	print "Addr32: $l\n";
	read BIN, $a32, $l*4;
	my @addr32 = unpack "L*", $a32;

	for ($i = 0; $i < scalar(@addr32); $i++)
	{
		printf "%08x\n", $addr32[$i]

	}
	exit;
};

@c = `objdump -r $ARGV[0]`; chomp @c;

@addr32 = ();
@addr16 = ();

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
	#	$secname eq '.text' and
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

print "count: $count\n";

open BIN, ">:raw", $ARGV[1] or die "Cant open file '$ARGV[1]': $!";

print BIN pack "l<", scalar(@addr16);
map { print BIN pack "S<", $_ } @addr16;
print BIN pack "l<", scalar(@addr32);
map { print BIN pack "L<", $_ } @addr32;

close BIN;
