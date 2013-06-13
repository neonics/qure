#!/usr/bin/perl
!($ARGV[0] && $ARGV[1]) and
	die "usage: symtab.pl <kernel.o> <kernel.sym> [-p] # -p=print\n";

# objdump -t has different output formats depending on the file format.
# This code parses the pe-i386 output format:
# [000](sec -1)(fl 0x00)(ty   0)(scl   6) (nx 0) 0x00000000 LABEL
# The elf output looks like:
# 00000000 l    d  .text	00000000 .text
# 00000000 l       *ABS*	00000000 CONSTANT
# 00000001 l       .text	00000000 label
#
# Verify if the object file is pe-i386
$_ = `objdump -a $ARGV[0]` or die;
if ( /file format pei-/s )
{
	$infile = $ARGV[0];
}
else
{
	$infile = "build/kernel.pe";
	`objcopy -O pei-i386 $ARGV[0] $infile`;
	# note: no 'or die' since objcopy returns error on success
}

@c = `objdump -t $infile` or die; chomp @c;

@tosort=();

map {
	($sec, undef, $a, $s) = /\[\d+\]\(sec\s*(.*?)\)(\(.*?\)\s?){4}(0x[0-9a-f]{8}) (\S+)/ and do {
		$sec ne -1 and do {
			push @tosort, sprintf("%08x:$sec:$s",hex $a);
		}

	}
} @c;

@symtab = sort @tosort;

@a=();
@s=();

map {
	($a,$sec,$s)=split /:/, $_;
	printf "%08x: %s\n", hex $a, $s if $ARGV[2] eq '-p';
	push @a, $a;
	push @s, $s;
} @symtab;

open BIN, ">:raw", $ARGV[1] or die "Cant open file '$ARGV[1]': $!";

print BIN pack "l<", scalar(@a);
map { print BIN pack "L<", hex $_ } @a;
$o=0;
map { print BIN pack "L<", $o; $o+=1+length $_ } @s;
map { print BIN pack "Z*", $_} @s;

close BIN;

