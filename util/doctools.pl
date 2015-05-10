#!/usr/bin/perl
#
# To see the documentation, run:
#
#  pod2man doctools.pl | nroff -man
#
#  if
#
#  perldoc (this file)
#
# doesn't work.


$W = "\x1b[1;33m";
$Z = "\x1b[0m";

%options = (
	dir	=> '.',
	type	=> undef,	# 'txt' or 'html'
	ignoremissing => 0
);

@responses = ();	# redirects

while ( $ARGV[0] =~ /^-/ )
{
	my $opt = shift @ARGV;

	$opt eq '-d' and $options{dir} = shift @ARGV || die "$opt: expect value" or
	$opt eq '-t' and $options{type} = shift @ARGV || die "$opt: expect value" or
	$opt eq '-i' and $options{ignoremissing} = 1
	or die "unknown option: $opt";
}

grep { $_ eq $options{type} } qw/txt html/ or die "unknown type: $options{type}" if defined $options{type};
$options{dir}=~s@/$@@;

my $command = shift @ARGV;

$command eq 'list' and do {
	print strip_type( map { $_->{n}."\n" }
	#grep {!$_->{label}}
	get_index() );
} or $command eq 'genlinks' and do {
	print genlinks( get_index() );
} or $command eq 'unlisted' and do {
	print difflist();
} or $command eq 'redirects' and do {
	print redirects();
} or die <<"EOF";
unknown command: $command

Usage:	$0 [options] <command> [command args]


options:
	-d <dir>	document directory; defaults to current directory
	-t <type>	filter on file extensions ("html", "txt"); default none
	-i		ignore missing files

commands:\n\tlist genlinks unlisted redirects
See the POD documentation for more (perldoc $0  --or--  pod2man $0 | nroff -man)
EOF

=pod

=head1 SYNOPSIS

doctools.pl [options] <command> [command args]

=head2 OPTIONS

-d <dir>	document directory; defaults to current directory

-t <type>	filter on file extensions ("html", "txt"); default none

-i		ignore missing files from the index. Without this option,
		missing files will not be listed or placed in the TOC.

=head2 COMMANDS

list		lists files. This is useful to construct dynamic
		dependencies in Makefiles.

genlinks	generate a HTML TOC of all the files.
 --mtime	fetch modification time from Git for all files, store them
		in the TOC, and include Javascript to calculate 'new',
		'updated', and 'tobeadded' labels.
 --tree		preserve tree structure from the indentation in index.
 --maxhours <h> maximum file age to be considered new/updated, default 1w.

unlisted	lists files in the directory not present in the index.
		this option requires there to be an index.

redirects	prints a list of redirects

=head1 DESCRIPTION

When no .index file is present in the document directory, the directory will
be examined for matching files, by default .html and .txt unless -t <type> is
given. When a .index file is present, only the files listed there will be used.

=head1 .index FORMAT

The .index file lists all .txt and .html files from the DOC directory that are
managed by this tool. Lines are stripped of comments (#). Empty lines are ignored.
Indentation is used to generate a tree structure: only indentation increments
are considered, not the depth itself per se.
Labels can be included by prefixing them with '='.

For example:

	=Foo
	  bar.txt
	    baz.html	# comment
	    bax.txt
	  doc.txt
	  =Grouping
	   one.txt
	    two.txt

will produce:

	<ul id="doclist">
	  <li>Foo
	    <ul>
	      <li><a href="bar.html">bar</a></li>
	      <ul>
	      	<li><a href="baz.html">baz</a></li>
	      	<li><a href="bax.html">bax</a></li>
	      </ul>
	      <li><a href="doc.html">doc</a></li>
	      <li>Grouping
	        <ul>
		  <li><a href="one.html">one</a>
		    <ul>
		      <li><a href="two.html">two</a></li>
		    </ul>
		  </li>
		</ul>
	      </li>
	    </ul>
	  </li>

(NOTE: at current, nested <ul> elements will appear under <ul> rather than <li>)


Further, HTTP redirect responses can be declared for moved documents:

	!301 Old.txt New.txt

is intended to produce a

	301 Permanently Moved
	Location: New.html

when requesting the old URL. This is accomplished by storing a file with the
redirect codes (TBD) that the webserver will consult when a document is not
found.


=cut

sub get_index {
	process_index (
		-f $options{dir}."/.index"
		? `cat $options{dir}/.index`
		: map {	s/^$options{dir}\///; $_ }
		(defined $options{type}
		? `ls $options{dir}/*.$options{type}`
		: `ls $options{dir}`)
	)
}

sub process_index {
	@_ = grep { ! /^\s*#/ } @_;	# no comment
	@_ = map { s/#.*$//; $_ } @_;
	@_ = map { s/\s*$//; $_ } @_;
	@_ = grep { /[^\s]+/ } @_;
	# normalize tree indent
	my $ld = 0, $ldn = 0;
	@_ = map { s/^(\s+)//; my $d=0+length($1); $ldn = $d==0?0: $d > $ld ? $ldn + 1 : $d < $ld ? $ldn -1 : $ldn; $ld=$d;
		{ n=>$_, d=>$ldn } } @_;
	#map { printf "%d %s\n", $_->{d}, $_->{n}} @_;
	@_ = grep { $_->{n}=~ /\.$options{type}$/ } @_ if $options{type};
	map { $_->{n} =~ /^=/ and $_->{label}=$' } @_;
	@_ = grep { if ( $_->{n} =~ /^\!(\d\d\d) (\S+) (\S+)/ ) { $_->{n} = $3; $_->{response}=[$1,$2,$3]; push @responses, $_; 0 } else {1} } @_;
	#die Dumper \@_;
	@_ = grep { my $a=$_->{n}; chomp $a; $_->{label} || -f $options{dir}."/".$a
		or do { warn "${W}WARNING: missing $options{dir}/$_->{n}$Z"; $options{ignoremissing}} } @_;
}

sub strip_type {
	map { s/\.$options{type}$//; $_ } @_;
}


sub redirects {
	get_index();

	print map {
		sprintf "%d %s.html %s.html\n",
			$_->{response}[0],
			($_->{response}[1] =~ /^(.*?)\.(txt|html)$/)[0],
			($_->{response}[2] =~ /^(.*?)\.(txt|html)$/)[0];
	} @responses;
}

sub difflist {
	-f $options{dir}."/.index" or die "no index";
	my @index =
		sort
		map { $_->{n}."\n" } grep { !$_->{label} }
		process_index( `cat $options{dir}/.index` );
	my @files = sort `ls $options{dir}`;

	# slow solution: O(n^2)
	my @unlisted =
		grep {my $f=$_; !grep{$_ eq $f} @index}
		@files;
}

sub reptag {
	my ( $count, $val, $baseindent ) = @_;
	my $ret = ""; while ( $count-->0 ) { $ret .= ( "  " x ($baseindent+1+$count) ) . $val; } $ret;
}

sub genlinks
{
	my %opts = (
		mtime	=> 0,
		maxhours=> '7 * 24',
		relpath	=> '',
		tree	=> 0
	);

	while ( scalar @ARGV ) {
		$_ = shift @ARGV;
		$_ eq '--mtime' and $opts{mtime} = 1 or
		$_ eq '--relpath' and $opts{relpath} = shift @ARGV || die "--relpath requires argument" or
		$_ eq '--maxhours' and
			$opts{maxhours} = shift @ARGV || die "--maxhours requires argument" or
		$_ eq '--tree' and $opts{tree} = 1
		or die "unknown argument to genlinks: $_";
	}

	%docs = $opts{mtime} ? getmtime( $options{dir} ) : undef;
	my $lastdepth = 0;

	join('',
	"<ul id='doclist'>\n",
		(map{
			my $modstring = "";
			$opts{mtime} and do {
				my $foo = $docs{$options{dir}.'/'.$_->{n}};
				$modstring = defined $foo
				? " mtime=\"$foo->{mtime}\" mod=\"$foo->{mod}\""
				: " mtime=\"today\" mod='N'";
			};

			my $pfx;
			my $indent = "  ";
			if ( $opts{tree} ) {
				$pfx .= reptag( $_->{d} - $lastdepth, "<ul>\n",  $lastdepth );
				$pfx .= reptag( $lastdepth - $_->{d}, "</ul>\n", $lastdepth-1 );
				$lastdepth = $_->{d};
				$indent = '  ' x (1+$_->{d});
			}

			$_->{n} =~ /^(.*?)\.(txt|html)$/;
			my $f = $1;
			my $t = $f; $t=~ tr/_/ /; $t =~ s@^.*?/(?=[^/]+$)@@;

			$_->{label} && !$opts{tree} ? () :
			( $pfx, $indent,
				"<li>",
				$_->{label} ? $_->{label} : "<a href=\"$opts{relpath}$f.html\"$modstring>$t</a>",
				"</li>\n"
			)
		}
		grep { ! /index\.html/ }
		@_),
		$opts{tree} ? reptag( $lastdepth, "</ul>\n" ) : "",
	"</ul>\n",
	!$opts{mtime} ? "" : <<HTML );

<style type="text/css">
span.new { margin-left: 1em; background-color: #0f0; font-style: italic; font-size: smaller}
span.updated { margin-left: 1em; background-color: yellow; font-style: italic; font-size: smaller}
span.tobeadded { margin-left: 1em; background-color: red; font-style: italic; font-size: smaller}
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

var modelabels = { 'A': 'new', 'M': 'updated', 'N': 'tobeadded'  };

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
		if ( !els.item(i).getAttribute('mod' ) )
			continue;
		if ( els.item(i).getAttribute('mtime' ) )
		{
			var hours = Math.round(
				( now - new Date( parsedate( els.item(i).getAttribute('mtime') ) ) ) /1000/3600
			);

			if ( hours >= maxhours )
				continue;
		}

		var span = document.createElement("span");
		var m = els.item(i).getAttribute( 'mod' );
		m = modelabels[m];
		span.innerHTML = m;
		span.setAttribute( "class", m );
		els.item(i).parentNode.appendChild( span );
	}
}

addlabels( 'doclist', $opts{maxhours});
</script>
HTML

}


# Retrieves the last modification time of documents.
sub getmtime {
	my $path = shift @_;

	my %docs;

	# TODO: cache

	$c=`git log --format=format:'%ai' --name-status -- $path`;
	@l=split(/\n\n/, $c);


	%docs;

	map
	{
		my @f = split(/\n/, $_);
		my $date = shift @f;

		map {
			my ($mod, $name) = /(.)\s+(.*)/ or die "illegal line: $_";

			# when calling this on repo/foo/docs/ from repo/foo,
			# the files will be named repo/foo/docs/X.
			# strip the path prefix:

			$name =~ /^(.*?\/)?($options{dir}.*)$/ and do { $name = $2; 1}
			or die "weird path: $name; expect it to be in $options{dir}";


			if ( $name =~ m@$options{dir}/[^/]+$@ ) {
				$docs{$name} = {
					mtime => $date,
					mod => $mod
				} unless exists $docs{$name};
			}
		} @f;

	} @l;

	return %docs;
}

