#!/usr/bin/perl
@l=<>;
chomp @l;
print "<ul>\n",
		(map{
			/^(.*?)\.html$/;
			"  <li><a href=\"doc/$_\">$1</a></li>\n"
		}
		@l),
	"</ul>\n";
