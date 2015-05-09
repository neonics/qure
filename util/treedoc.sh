#!/bin/bash
git ls-files | perl -MData::Dumper -e ' while (<>) {
	chomp; @a = split m@/@; $b = pop @a; $q++;
	$root //= {};
	$cur=$root; 
	map {
		$cur->{$_}//={files=>[]};
		push @{ $cur->{$_}{files} }, $b;
		$cur=$cur->{$_}
	} @a;
	};
	#print join " - ", @a; print " ($q) ($cur)\n", Dumper $root;

	print "\n\n";

	sub render($;$) {
		my $indent = $_[1];# // "";
		print "$indent<ul>\n";
		map {
			print "$indent<li>$_\n";
			scalar keys %{ $_[0]->{$_} } > 1 and do {
			render( $_[0]->{$_}, "$indent  " );
			};
		}
		grep { $_ ne "files" }
		keys %{ $_[0] };
		print "$indent</ul>\n";
	}


	print "
	<div style=\"float:left; margin-right: 10em;\">
	";

	render( $root );

	print "
	</div>
	<div>
		<pre>
		# TODO: make template file for toc,
		# and add bootstrap/jquery for showing the
		# files in the right box
		</pre>
	</div>
	<br style=\"clear: both; float:none; display:block;\"/>
	<!-- end tree -->\n";


	
	'
