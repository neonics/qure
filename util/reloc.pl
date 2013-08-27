#!/usr/bin/perl
getopt(@ARGV) or
	die "usage: reloc.pl [[-C [-R]] <kernel.o>] <kernel.reloc>\n\t-C: compress\n";

$VERBOSE = 1;
$ADDR16 = 0;	# set to 0 to clobber 16-bit relocation entries.
$RLE = $opt{rle};
$RLE_NO_TABLE = $opt{rle_no_table};	# set to 1 to have no RLE repeat count lookup table

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

		$RLE = $deltawidth >> 7;
		$deltawidth &= 0x7f;

		if ( $RLE )
		{
			read BIN, $rlewidth, 1;
			read BIN, $rleidxwidth, 1;
			read BIN, $rlecount, 2;
			read BIN, $rleocc, 2;
			$rlecount = unpack "S<", $rlecount;
			$rlewidth = unpack "C", $rlewidth;
			$rleidxwidth = unpack "C", $rleidxwidth;
			$rleocc = unpack "C", $rleocc;
		}
		$VERBOSE and
			printf "addr32 count: %d, alphabet: %d width %d, delta: width %d, RLE: width %d count %d idx width %d\n",
			$l, $alphabet, $alphawidth, $deltawidth, $rlewidth, $rlecount, $rleidxwidth;

		read BIN, $a, ($alphawidth>>3) * $alphabet or die;
		@alphabet = unpack &wordp($alphawidth).'*', $a;

		if ( $RLE ) {	# can be left enabled without problem
			$rlecount and (read BIN, $a, ($rlewidth>>3) * $rlecount or die)
			or $a=0;
			@rle = unpack &wordp($rlewidth).'*', $a;
		}

		%d2i, %i2d, $index=0;	# create lookup table for delta indices
		map { $i2d{$index} = $_; $d2i{$_} = $index++; } @alphabet;#sort {$a<=>$b} keys %count;

		$VERBOSE > 1 and do {
			map { printf "TABLE index %3d -> delta %08x\n", $_, $i2d{$_} }
			sort{$a<=>$b} keys %i2d;
			map { printf "TABLE delta %08x -> index %3d\n", $_, $d2i{$_} }
			sort{$a<=>$b} keys %d2i;
		};


		if ( $RLE )
		{
			# calculate deltasize:
			# $l = number of delta entries in total, some of which
			# are RLE instructions.
			# $rleocc = number of RLE instructions
			# RLE instruction size:
			#   2 * ($deltawidth>>3) + ($rleidxwidth>>3)

			my $dtsize = ($deltawidth>>3) * ($l-$rleocc)
				+ ((2*$deltawidth + $rleidxwidth)>>3)*$rleocc;


			read BIN, $data, $dtsize;#($deltawidth>>3) * $l;
			@delta = unpack 'C*', $data; # byte array
			for ($i = 0; $i < scalar @delta; ) # readbits:$i+= $deltawidth>>3 )
			{
			#	$_ = $delta[$i];
				$_ = &readbits( \@delta, \$i, $deltawidth );

				if ( $_ == (1<<$deltawidth) -1 ) {

					# read count
					$cnt = &readbits(\@delta, \$i, $rleidxwidth);
					$rlecount and $cnt = $rle[$cnt];
					$cnt++;

					# read delta
					$_ = &readbits( \@delta, \$i, $deltawidth );
					print "REPEAT $cnt\n";
					for ($foo=0;$foo < $cnt; $foo++)
					{
						printf " idx %3d (%02x) delta %08x addr %08x\n",
							$_, $_, $i2d{$_}, $a+=$i2d{$_};
					}
				} else {
					printf "idx %3d (%02x) delta %08x addr %08x\n",
						$_, $_, $i2d{$_}, $a+=$i2d{$_}
				}
			}
		} else {
		read BIN, $a, ($deltawidth>>3) * $l;
		@delta = unpack &wordp($deltawidth).'*', $a;

		$a = 0;
		map { printf "idx %3d (%02x) delta %08x addr %08x\n",
			$_, $_, $i2d{$_}, $a+=$i2d{$_}
		} @delta;
		}
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


my %syms = &getsyminfo( $ARGV[0] );

#printf "SYM .data: %s, %s\n", $syms{'.data'}{type}, $syms{'.data'}{addr};
#map { if (/^\./) { print "$_: $syms{$_}{type}\n"}} keys %syms;
#print "\n";
#die;

&parse_reloc( $ARGV[0] );

&write_table( $ARGV[1], $opt{compressed} );

########### end


sub parse_reloc
{
	my ($filename) = @_;

	my $tmpfile = "$filename.coff-reloc";
	unlink $tmpfile if -f $tmpfile;

	my @c = `objdump -h $filename`;
	if ( grep { /\.reloc/ } @c )
	{
		@c = `objcopy -j .reloc $filename $tmpfile`;
	}

	if ( -f $tmpfile )
	{
		print "parsing PE/COFF relocation table\n";
		@addr32 = &parse_pecoff_reloc( $tmpfile );
	}
	else
	{
		my @c = `objdump -r -j .text $filename`
		or die "can't read object file $filename: $!";
		chomp @c;
		&parse_objdump_reloc( @c );
	}
}


sub parse_objdump_reloc
{
	my @c = @_;
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
		/([0-9a-f]+)\s+(16|DISP32)\s+(\S+)/
		or
		/([0-9a-f]+)\s+(DISP16)\s+(\S+)/ and do {
			die "16bit symbol displacement: $_\n"
			. "reference 32bit symbol from 16 bit text segment?";
		}
		or
		/([0-9a-f]+)\s+(dir32)\s+(\S+)/ and do
		{
			# .strtab section: compact pointer array: data decl, code ref
			# .stab: source table.
			# .stabstr: source string table
			# .text: as -R (fold data in text) results in .data
			#   relocations being mentioned in .text.
			# So we (for now) only need to worry about the .text.
			$secname eq '.text' and
			do
			{

				my $a = hex $1;
				my $t = $2;
				my $v = $3;

				# sanitize
				my ($l, $op, $o) = $v=~/^([^-]+)(\+|-)([^-]+)$/; #split /-/, $v;

#				print "$secname [",sprintf("%08x",$a),"] [$t] [$v] [$l:$o]";

				if ( defined $l )
				{
					$o=hex $o;


					if ($syms{$l}{type} eq 'A')
					{
#					print "$secname [",sprintf("%08x",$a),"] [$t] [$v] [$l:$o]";
#					printf "($l:%s, %08x, d %08x)",
#						$syms{$l}{type}, $syms{$l}{addr},
#						$o-$syms{$l}{addr};
#						print " A";
#						print "\n";
					}
					else
					{
					$t ne '16' and
						push @addr32, $a;
#						print " +";
					}
				}
				else
				{
					$t eq '16'
						? push @addr16, $a
						: push @addr32, $a;
				}

#				print "\n";
			};
			1
		}
		or /^\s*$/
		or /^\S+:\s+file format/
		or die "invalid line (count=$count): '$_'\n",

	} @_;
}


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
		if ($RLE){
			%rle, %repdic, %repstat, $ld=-1, $repcnt, $reps, $i=0, $rleocc;
			push @addr32, 0xffffffff; # to flush the last bit
		}
		map {
			$d=$_ - $l; $l=$_; 			# delta
			$m=$m<$d?$d:$m unless $_==0xffffffff;	# max
			$count{$d}++; $bitfreq{log2($d|1)}++;	# delta freq

			if ( $RLE )
			{
				if ( $ld == $d )
				{
					$VERBOSE > 1 and print "+";
					$repcnt++;
				}
				else
				{
					$VERBOSE > 1 and print "-";
					if ( $repcnt > 2 )	# min rep before space loss
					{
						$VERBOSE > 1 and
						printf "[$repcnt;$reps;%04x]", $ld;

						push @delta, $rle{$reps}=0x80000000 | $repcnt | ($ld<<16);
						push @delta, $ld;

						$repdic{$repcnt}++;
						$repstat{$repcnt}{$ld}++;
						$rleocc++;
					}
					elsif ($repcnt) {
						# repeat count too low for space gain.
						push @delta, $ld
						while ($repcnt -- + 1);

					}
					elsif ($ld!=-1) {
						push @delta, $ld;
					}
					$repcnt = 0; $reps = $i;
				$ld=$d;
				}
				$i++;
			} else {
				push @delta, $d;
			}
		} @addr32;

		if ( $RLE )
		{
			$VERBOSE > 1 and
			do {
				map { printf "repcount %4d occurrence %d\n", $_, $repdic{$_} }
				sort {$a<=>$b} keys %repdic;
				printf "Repetition dictionary size: %d\n", scalar keys %repdic;
			};

			$repmax=0;
			@rle = map {$repmax<$_ and $repmax=$_; $_} sort {$a<=>$b} keys %repdic;
			%reptab, $i=0;
			map { $reptab{$_}=$i++ } @rle;
		}

		# print alphabet table size (entries) and entry width in bits.
		print BIN pack "S<", $alphabet=scalar keys %count;
		print BIN pack "C", $kw=words(log2($m|1));
		# alphabet increased: one token used for repetition (max)
		print BIN pack "C", ($RLE?0x80:0)|($dw=words(log2($alphabet+($RLE?1:0)))); $ds=wordp($dw);# delta width
		if ( $RLE ) {
@rle=() if $RLE_NO_TABLE;
		print BIN pack "C", $rw=scalar @rle ? words(log2($repmax)) : 0;
		print BIN pack "C", $riw=words(log2(scalar @rle?scalar @rle:$repmax));
		print BIN pack "S<", scalar @rle;
		print BIN pack "s<", $rleocc;
		}
		print BIN pack "S*", sort {$a<=>$b} keys %count;	# alphabet
		$VERBOSE and
			printf " alpha $alphabet width $kw, delta width $dw";

		if ( $RLE ) { # write RLE table
			$VERBOSE and printf ", RLE width %d, count %d, idx width %d\n",
				$rw, scalar @rle, $riw;
		scalar @rle and
		print BIN pack wordp($rw)."*", @rle;
		} else {
			$VERBOSE and print "\n";
		}

		$VERBOSE > 1 and do {
			map { printf "alphabet: %08x\n", $_ } sort {$a<=>$b} keys %count;
			map { printf "delta width frequency: %d: %d\n", $_, $size{$_} }
			sort {$a<=>$b} keys %size;
		};

		%d2i, %i2d, $index=0;	# create lookup table for delta indices
		map { $i2d{$index} = $_; $d2i{$_} = $index++; } sort {$a<=>$b} keys %count;
		$VERBOSE > 2 and do {
			map { printf "TABLE index %3d -> delta %08x\n", $_, $i2d{$_} }
			sort{$a<=>$b} keys %i2d;
			map { printf "TABLE delta %08x -> index %3d\n", $_, $d2i{$_} }
			sort{$a<=>$b} keys %d2i;
		};

		# write delta indices
		if ( $RLE ) {
		$a=0, $rep=0;
		map {
			$VERBOSE > 1 and printf "[%08x] ", $_;
			if ( $_ & 0x80000000 ) {
				$rep = $repv = $_&0xffff;
				$repv = $reptab{$rep} if scalar @rle;
				# write rep prefix
				print BIN pack wordp($dw), (1<<$dw)-1;	# highest delta idx
				print BIN pack wordp($riw), $repv;	# repeat (index)
				$rep++; # repeat implies at least two!
				$VERBOSE > 1 and print "REP $rep\n";
			}
			else {
				do {
					$a+=$_;
					$VERBOSE > 1 and
					printf "delta %08x idx %02x ADDR %08x\n",
						$_, $d2i{$_}, $a;
				} while (--$rep>0);
				print BIN pack wordp($dw), $d2i{$_}
			}
		} @delta;
		} else {
			map { print BIN pack &wordp($dw), $d2i{$_} } @delta;
		}
	}
	else
	{
		$VERBOSE and print "\n";
		map { print BIN pack "L<", $_ } @addr32;
		$l=0;
		$VERBOSE > 1 and do {
			map { printf "%5d addr32 %08x delta %08x\n",
				$i++, $_, $_-$l; $l=$_;} @addr32;
		}
	}

	close BIN;
}


sub readbits
{
	my ( $bytearrayref, $byteindexref, $bits ) = @_;

	$_ = $$bytearrayref[$$byteindexref++];

	$bits >= 16 and
	$_ |= $$bytearrayref[$$byteindexref++] << 8;

	$bits == 32 and do {
	$_ |= $$bytearrayref[$$byteindexref++] << 16;
	$_ |= $$bytearrayref[$$byteindexref++] << 24;
	};

	$_;
}

sub getopt
{
	while ($ARGV[0] && $ARGV[0] =~ /^-/)
	{
		$ARGV[0] eq '-C' and ($opt{compressed} = shift @ARGV) or
		$ARGV[0] eq '-L' and ($opt{rle_no_table} = shift @ARGV) or
		$ARGV[0] eq '-R' and ($opt{rle} = shift @ARGV) or return 0;
	}
	$ARGV[0];
}


sub parse_pecoff_reloc
{
	my ($filename) = @_;
#	system "objcopy -j .reloc kernel.obj kernel.reloc";# or die $!;

	open BIN, "<:raw", $filename or die;
	$s = (stat BIN)[7];

	$PAGE_RVA_ADJUST = undef;

	# array of blocks, eack refers to 4k page. must start at 32 bit
	# boundary
	read BIN, $data, 0x1000;	# unknown data;; at 0xf4 is '.reloc',
					# lots of 0 until 0x1000: word[].
	$pos = 0x1000;

	my @addr;

	do
	{
		read BIN, $data, 8;
		$pos += 8;
		my ($page_rva, $block_size) = unpack "L<L<", $data;

		# we'll assume that the first entry/page refers to
		# the first page. The page_rva starts at 0xffc23000 for
		# some reason, so we subtract that.
		$PAGE_RVA_ADJUST = $page_rva unless defined $PAGE_RVA_ADJUST;

		printf "%08x - Base Relocation Block: page rva %08x block size %08x\n",
			$pos-8,
			$page_rva - $PAGE_RVA_ADJUST, $block_size;

		#die if ($block_size -8 < 0);
		if ( $block_size )
		{
			read BIN, $data, $block_size-8;
			$pos += $block_size-8;

			my @relocs = unpack "S<*", $data;

			if ( $relocs[ scalar(@relocs)-1] == 0 )
			{
				pop @relocs;
			}

			map
			{
				my ($t, $v) = ($_>>12, $_&((1<<12)-1));
				printf "  %08x $t (%s)\n", $v + $page_rva - $PAGE_RVA_ADJUST,
					qw/ABS HI LO HILO HIADJ MIPS ARM ARM MIPS DIR64/[$t];

				push @addr, $_ + $page_rva - $PAGE_RVA_ADJUST;
			}
			@relocs;
		}

		while ($pos & 3) { read BIN, $data, 1; $pos++}
	} while ($pos < $s);

	close BIN;

	@addr;
}



sub getsyminfo
{
	my ($filename) = @_;

	my @c = `nm $filename` or die "$!";
	chomp @c;

	my %syms;

	map
	{
		my ($a, $t, $n)=/^([0-9a-f]{8}| {8}) (.) (\S+)$/ or die "invalid nm output: $_";

		if ( $a eq '        ' )
		{
			$syms{$s} = {type=>$t};
#			printf "%s [%s] %s\n", $a, $t, $n;
		}
		else
		{
			$a = hex $a;
			$syms{$n} = {addr=>$a, type=>$t};
#			printf "%08x [%s] %s\n", $a, $t, $n;
		}

	}
	@c;

	return (%syms);
}

=pod

=head1 NAME

	B<reloc.pl> - relocation table converter

=head1 SYNOPSYS

=over

=item	reloc.pl [[-C] [-R [-L]] objectfile.o] my.reloc

=item	reloc.pl objectfile.o my.reloc

=item	reloc.pl my.reloc

=back


=head1 DESCRIPTION

reloc.pl will use B<objdump> to extract relocation table information
and write it in a simple format, as explained below. Optionally
it can compress the relocation table.

Generated relocation tables are stored in the RAMDISK of the bootloader
which uses them to relocate the kernel.

=head1 OPTIONS

B<-C>	compress the generated relocation file

B<-R>	use RLE compression (requires -C)

B<-L>	do not write RLE-repeat count table (requires -R)


=head1 Development Evolutionary Stages


The next subsections describe the steps taken to add compression, to clarify
the format.


=head2 Stage 1: simple arrays

The first implementation makes use of a simple array scheme,
where a dword, specifying the number of elements to follow,
is followed by that number of elements.

Format:

	dword	16-bit address count
	word[]	16-bit addresses
	dword	32-bit address count
	dword[]	32-bit addresses

=head2 Stage 2: delta compression

Now, instead of 32 bit addresses, the delta (difference) between each
two consecutive addresses is stored. These generally do not exceed
16 bits, and thus the 32 bit address table can be compressed by 50%.


	Note that there is no compression as yet for 16 bit addresses since
	they are unused. So we will only describe the 32-bit part of the file.
	The first dword of the file will be 0, indicating no 16 bit addresses.

Format:

	dword	32-bit address count | 0x40000000 # delta compression
	word[]	16-bit delta.

This format is an intermediary development format and not committed.

=head2 Stage 3: alphabet lookup table

After generating a frequency distribution table for the delta's, it turned
out that there were only 218 different delta values being used, which fits
in a byte.
Therefore, a table is inserted listing all the different delta's. Since
the delta's don't exceed 16 bits, their width in bits is stored, aswell
as the number of unique delta's.
The word 'alpha' or 'alphabet' is used to indicate the dictionary of unique
delta values.
The delta table is the array of delta-indices, or, alphabet indices.

Format:

	dword	32-bit address count | 0x40000000
	word	alphabet count (unique deltas in use) (i.e. 218)
	byte	alphabet character width in bits (i.e. 16)
	byte	delta (alphabet lookup) character width in bits (i.e. 8).

	?[]	alphabet	(i.e. word[])
	?[]	delta-indices	(i.e. byte[]).

Note that bit-widths are stored rounded up to 8, 16, or 32. Fewer bits
can be used to encode a power of two, but it is foreseen that future
compression will use a bitstream for more compact compression.

The process of generating the addresses is to read each delta-index,
look up the delta-value in the alphabet table, and add it to the current
address.


=head2 Stage 4: Run-Length Encoding

There are many places (97 or so) where a delta repeats many times.
A dictionary character - the highest value fitting in a delta-index value -
is used as an RLE-prefix opcode. When this value is encountered, the next
value is not a delta-index, but a repeat number. This number can have
a different size than the delta's, so this size is stored.
Further, this repeat-count number can either be a direct number, or
an index to an RLE table entry.

Format:

	dword	32-bit address count | 0x40000000
	word	alphabet count
	byte	alphabet character width in bits | 0x80
	byte	delta (alphabet index) character width in bits

	byte	RLE table entry width in bits
	byte	repeat-index width in bits
	word	RLE table entry count
	?[]	repeat-index values

	?[]	alphabet of delta values
	?[]	delta-indices / RLE prefix / repeat-index

When a delta index is read, it is checked against the maximum value,
and if so, is considered an RLE prefix. The following value is read,
using the repeat-index width in bits, which may differ from the delta-index
width. This is then potentially looked up in the repeat-index table.
The next value in the delta-index table will be the delta-index to repeat.

=cut


