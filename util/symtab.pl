#!/usr/bin/perl
!($ARGV[0] && $ARGV[1]) and
	die "usage: symtab.pl <kernel.o> <kernel.sym> [-p] # -p=print\n";

@c = `objdump -t $ARGV[0]`; chomp @c;

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
