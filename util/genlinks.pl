#!/usr/bin/perl

if ( $ARGV[0] eq '--mtime' )
{
	shift @ARGV;

	$maxhours = 7 * 24;	# one week

	if ( $ARGV[0] eq '--maxhours' )
	{ shift @ARGV; $maxhours = $ARGV[0] or die "require hours argument"}


	%docs = getmtime( 'DOC/' );

	#map { printf "%-40s  [%s] %s\n", $_, $docs{$_}{mod}, $docs{$_}{mtime}; }
	#sort { $docs{$a} cmp $docs{$b} }
	#keys %docs;


#########################################################
#

	@l=`ls root/www/doc/*.html`;#<>;
	chomp @l;
	print "<ul id='doclist'>\n",
		(map{
			my $h = $_;
			$h=~ s@^root/www/doc/@@;
			my $t = $h;
			$t =~ s@\.html$@.txt@;
			my $foo = $docs{'DOC/'.$t};
			$foo = $docs{'DOC/'.$h} unless defined $foo;

			my $modstring = defined $foo
				? " mtime=\"$foo->{mtime}\" mod=\"$foo->{mod}\""
				: "";
			$h =~ /^(.*?)\.html$/;
			"  <li><a href=\"doc/$h\"$modstring>$1</a></li>\n"
		}
		@l),
	"</ul>\n";

	print <<EOF;
<style type="text/css">
span.new { margin-left: 1em; background-color: #0f0; font-style: italic; font-size: smaller}
span.updated { margin-left: 1em; background-color: yellow; font-style: italic; font-size: smaller}
</style>

<script type='text/javascript'>

function numpad( num, width ) {
	var ret = "" + num;
	while ( ret.length < width )
		ret = '0' + ret;
	return ret;
}

function isotz( mins ) {
	var ret;
	if ( mins < 0 )
	{	ret = '-'; mins =-mins;}
	else
		ret = '+';

	return ret + numpad( mins / 60, 2 ) + numpad( mins % 60, 2 );
}

/**
 * in:  "YYYY-MM-DD hh:mm:ss +0000" (where +0000 may be -0000 or Z, and 0000 the usual);
 * out: "YYYY-MM-DDThh:mm:ss.000+0000"
 */
function parsedate( s )
{
	var l = s.split(/ /);
	return l[0] + 'T' + l[1] + '.000' + l[2];
}

/** in: Date object;
 *  in: iso = optional; when true, reeturns simplified ISO 8601 extended fmt (see parsedate)
 *  out: string
 */
function isodate( d, iso )
{
 return "" +
	d.getFullYear() + '-' +
	numpad( d.getMonth()+1, 2 ) + '-' +
	numpad( d.getDate(), 2 ) + (iso?'T':' ') +
	numpad( d.getHours(), 2) + ':' +
	numpad( d.getMinutes(), 2) + ':' +
	numpad( d.getSeconds(), 2) + (iso?'.000':' ') +
	isotz( d.getTimezoneOffset() );
}

var modelabels = { 'A': 'new', 'M': 'updated'  };

/**
 * given an element, it scans all <a> tags for 'mtime' and 'mod'
 * attributes, and appends 'new' and 'updated' spans if the mtime
 * is not older than maxhours.
*/
function addlabels( id, maxhours ) {
	maxhours = maxhours || 7 * 24;
	var d = document.getElementById( id || 'docs' );

	var now = new Date();

	var els = d.getElementsByTagName( 'a' );
	for ( i=0; i < els.length; i ++ ) {
		if ( !els.item(i).getAttribute('mtime' ) )
			continue;

		var hours = Math.round(
			( now - new Date( parsedate( els.item(i).getAttribute('mtime') ) ) ) /1000/3600
		);

		if ( hours < maxhours )
		{
			var span = document.createElement("span");
			var m = els.item(i).getAttribute( 'mod' );
			m = modelabels[m];
			span.innerHTML = m;
			span.setAttribute( "class", m );
			els.item(i).parentNode.appendChild( span );
		}

	}
}

addlabels( 'doclist', $maxhours);
</script>
EOF

}
else	# legacy
{
	@l=<>;
	chomp @l;
	print "<ul>\n",
			(map{
				/^(.*?)\.html$/;
				"  <li><a href=\"doc/$_\">$1</a></li>\n"
			}
			@l),
		"</ul>\n";
}




# Retrieves the last modification time of documents.
sub getmtime {
	my $path = shift @_;

	my %docs;

	$c=`git log --format=format:'%ai' --name-status -- $path`;
	@l=split(/\n\n/, $c);

	%docs;

	map
	{
		my @f = split(/\n/, $_);
		my $date = shift @f;

		map {
			my ($mod, $name) = /(.)\s+(.*)/ or die "illegal line: $_";

			if ( $name =~ m@DOC/[^/]+$@ ) {
				$docs{$name} = {
					mtime => $date,
					mod => $mod
				} unless exists $docs{$name};
			}
		} @f;

	} @l;

	return %docs;
}
