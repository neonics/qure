#!/usr/bin/perl
!($ARGV[0])# && $ARGV[1])
	and
	die "usage: stringdata.pl <kernel.obj0.r>\n";

$infile = shift @ARGV;

-f "$infile.strings" and unlink "$infile.strings";
system "objcopy -j .strings $infile $infile.strings";

open IN, "<:raw", "$infile.strings" or die $!;
$size = (stat IN)[7]; print "size: $size\n";
read IN, $data, $size or die $!;
close IN;

#my $cnt = $data=~ tr/\0// -1;
#print "count: $cnt\n";
my @strings = unpack( '(Z*)*', $data);
print "count: ",  scalar(@strings), "\n";

my $data2 = pack( '(Z*)*', @strings);
print "data len: ", length($data),"\n";
print "data2 len: ", length($data2),"\n";

%dups;
$last=undef;

map {
	if ( $_ eq $last)
	{
		$dups{$_}++;
	}
	$last=$_;

	if (0){
		$_=~s/\n/\\n/g;
		$_=~s/\r/\\r/g;
		$_=~s/\t/\\t/g;
		printf " - [%2d] '$_'", length($_);
		if (length($_)==0) { print "<<EMPTY>>";}
		if (length($_)==1) { print "<< " ,ord($_)," >>";}
		if (length($_)==2) { print "<< " ,ord($_)," >>";}
		print "\n";
	}
} sort @strings;

print "Duplicates:\n";
$duplen=0;
map {
	printf " %2dx [%2d] $_\n", 1+$dups{$_}, length $_;
	$duplen += $dups{$_}*(1+length $_);
} keys %dups;

printf "Total space save: %d / %d = %d %%\n",
	$duplen, length($data), 100*$duplen/length($data);

@nondups = grep { ! exists $dups{$_} } @strings;
printf "Unique strings: %d  (Duplicated strings: %d)\n", scalar(@nondups),
	scalar keys %dups;

#@nondups = ( 'foobar', 'bar');
$suffixsave=0;

$ignorecase=1;

foreach my $s (@nondups)
{
#	print "Find strings suffixing $s\n";
	my $suffixes=0;
	my $lastm=undef;
	map
	{
		#if ( /$s$/ )
		my $idx = $ignorecase ? rindex(lc($_),lc($s)):rindex($_,$s);
		if ( $idx>0)
		{
			#print " - check $_: match at $idx";

			if ( length($_)==$idx+length($s))
			{ $suffixes++; $lastm=$_;
				#print " -- end match. SFX=$suffixes\n";
			}
			else{
				#print " -- NAK\n";
			}
		}
	}
	grep { $s ne $_ }
	@nondups;

	printf " %3d Suffix matches for $s, such as: %s\n", $suffixes, $lastm
	if $suffixes>0;

	$suffixsave += $suffixes<=0 ? 0 : length($s)+1;
}
printf "Suffix compression saves %d bytes\n", $suffixsave;
