#!/usr/bin/perl

@conditions = qw/ e ne a   be ae  b  g   le ge  l  p  np c nc o no s ns/;
@alias =      qw/ z nz nbe na nb nae nle ng nl nge pe po /;
@opposite; map { $opposite[$_] = $conditions[$_+1-2*($_&1)] } 0..$#conditions;
#map{ printf "%-3s %-3s\n", $conditions[$_], $opposite[$_]; }0..$#conditions;

print <<"EOF";
.macro cmov cond, invcond, src, dst
	.if INTEL_ARCHITECTURE >= 6
		cmov\\cond	\\src, \\dst
	.else
		j\\invcond	600f
		mov	\\src, \\dst
600:
	.endif
.endm
EOF
map {
	print <<"EOF";
.macro cmov$conditions[$_] src, dst
	cmov $conditions[$_], $opposite[$_], \\src, \\dst
.endm
EOF
	$alias[$_] and print <<"EOF";
cmov$alias[$_]=cmov$conditions[$_]
EOF
} 0..$#conditions; # @conditions;
print "\n";
