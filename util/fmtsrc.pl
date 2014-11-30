#!/usr/bin/perl
#
# Format assembly source code.

use FindBin;
use lib $FindBin::Bin;
use Template;

my ($PATH) = $0=~/^(.*)\/[^\/]*$/;

$VERBOSE = 0;

$dir="./";
$incremental = 1;

$template = undef;	# Template object
$opt = {};

while ( $ARGV[0] =~ /^-/ )
{
	$_ = shift @ARGV;

	$_ eq '-h' || $_ eq '--help' and usage()

	or $_ eq "--dir" and $dir = shift @ARGV
	or $_ eq '-v' and $VERBOSE++
	or $_ eq "-i" and $incremental = 1	# TODO

	or $_ eq "--template" and do {
		$template = new Template;
		@ARGV = $template->args( "-t", @ARGV );
	}

	or $_ eq '--index-header' and do { $opt->{index_header}='${include '.shift(@ARGV).'}'; 1 }

	or die "Unknown option: $_";
}

defined $template or do {
	$template = new Template;
	$template->args( "--template", "none" );
};


# unique  (not needed if $^ is used in makefile)
#my %infiles; foreach (@ARGV) { $infiles{$_}=1; }; @ARGV = keys %infiles; print "INFILES: @ARGV\n";

$numfiles = scalar(@ARGV) or die "Missing filename";
# Argument's set up.


@ref = readref("${dir}src.ref");	# read cached references

$VERBOSE and printf "Read reference: %d entries\n", scalar @ref;

@files;# = map { process_source( $_ ) } @ARGV;
while ( scalar @ARGV ) { push @files, process_source( shift @ARGV ); }

writeref("${dir}src.ref", @ref);

writehtml( "${dir}index.html", "Index",
	$opt->{index_header},
	map { my $b=$_; $b=~tr@/@_@; "<a href='$b.html'>$_</a><br/>\n" }
	sort {$a cmp $b}
	uniq( map { $_->{file} } @ref )
);

foreach ( @files ) {
	my $f = $_->{file}; $f=~tr@/@_@;

	# add references
	$_->{content} =~ s@(<span class="glabelref">\s*)([^<\s]+)(\s*</span>)@$1.getref($_, "$2").$3@ge;
	$_->{content} =~ s@(<span class="glabeldecl">\s*)([^<\s]+)(\s*</span>)@$1.getref($_, "$2").$3@ge;

	writehtml( $dir.$f.".html", $_->{file}, $_->{content} );
}
printf "Processing %40s [100%]\n", "";


############################################################################
# Utility

sub usage {
	print <<"EOF";
Usage: $0 [options] [template-options] <file.s> [out.html]

options:
	-h --help	this help message (<file.s> can be omitted)
	--dir <dir>	the output directory; defaults to '.'
	-v		increase verbosity
	-i		incremental; uses src.ref in <dir>
	--template <..>	speficy template name to use. This also begins
			template arguments; the rest of the options will
			be passed on to the Template argument parser.
			(Note: template-options: the first option MUST be
			--template (and not -t!)
EOF
	Template::usage();
	exit 1;
}


sub writehtml {
	my ($filename, $title, @content) = @_;

	$VERBOSE and print "Writing HTML: $filename, $title\n";

	open OUT, ">", $filename or die "can't write $filename: $!";
	print OUT $template->process( join('', @content),
		{ title => $template->{title}." ".$title }
	);
	close OUT;
}



sub uniq {
	my %h=();
	foreach (@_) { $h{$_} = $_ };
	keys %h;
}
############################################################################
# Symbol Reference Cache

sub getref {
	my ($src, $name) = @_;

	defined $src and
	grep { $_->{name} eq $name } @{ $src->{labels} } and
		return "<a href='#$name'>$name</a>";

#	foreach ( @files ) {
#		grep { $_->{name} eq $name } @{ $_->{labels} } and do {
#			my $f=$_->{file}; $f=~tr@/@_@;
#			return "<a href='$f.html#$name'>$name</a>";
#		}
#	}

	foreach ( @ref ) {
		$_->{name} eq $name and do {
			my $f=$_->{file}; $f=~tr@/@_@;
			return "<a href='$f.html#$name'>$name</a>";
		}
	}


	return "<span class='undefined'>$name</span>";
}

sub readref {
	my @l=();
	my $reffile = shift @_;
	-f $reffile and do {
		open INREF, "<", $reffile or die "can't read $reffile: $!";
		@l = <INREF>;
		close INREF;
	};

	my $ln = 0;
	map {
		$ln++;
		/^([^:]+):(\d+)\t(\S+)$/ or die "illegal ref line: $reffile:$ln: $_";
		{ file => $1, line => $2, name => $3 }
	} @l
}

sub writeref {
	my $reffile = shift @_;
	$VERBOSE and printf "Writing %d references to $reffile\n", scalar(@_);
	open OUTREF, ">", $reffile or die "can't create $reffile: $!";
	print OUTREF map { sprintf "%s:%d\t%s\n", $_->{file}, $_->{line}, $_->{name} } @_;
	close OUTREF;
}

# removes all symbol reference declarations for the given file
sub filterref {
	my ( $file, @r ) = @_;

	grep { $_->{file} ne $file } @r;
}


sub style {
	return <<EOF;
<style type="text/css">
	.code { font-family: courier, monospace;
		background-color: black;
		color: white;
		font-size: 10pt;
		width: 480pt;
	}

	.code a { color: inherit; text-decoration: underline; }

	.undefined { background-color: red } /* undefined reference */


	.comment { color: #888; }
	.comment span { color: #888; }

	.glabelref { color: #0f0; } /* global label */
	.glabeldecl { color: #0f0; } /* global label declaration */
	.glabeldef { color: #0f0; } /* global label definition */
	.unlabeldecl { color: green; } /* unnamed local label */
	.unlabelref { color: green; } /* unnamed local label */

	.gpr { color: cyan; /* is #0ff*/}
	.segr { color: #ff2200; }
	.cr { color: red; }
	.dr { color: blue; }

	.t { color: #f08; }

	.dir { color: #f0f; /*purple;*/ }
	.seg { color: red }
	.data { color: #44f; }

	.const { color: #955; }
	.constdecl { color: #955; }
	.hex { color: #595; }
	.bin { color: #595; }
	.dec { color: #595; }
	.memref { color: #0f0; }

	.str { color: #88f; }
	.str span { color: #88f; }
	.lit { color: #99f;}
	.lit span { color: #99f;}

	.is { color: yellow; /* ff0 */ } /* instr stack */
	.ic { color: orange; } /* instr control */
	.il { color: #8a4; } /* instr loop */
</style>
EOF
}


sub process_source {
	my @labels=(), @const=();
	my $file = $_[0];
	my $line=0;
	my $out="";

	$|=1;
	printf "Processing %-40s [%3d%%]  \r", $file, 100.0 * (1+scalar @files)/$numfiles -1;

	open IN, "<", $file or die "can't read $file: $!";
	my $f = $file; $f=~s@/@_@g;

	$out .= style() . '<pre class="code">',"\n";

	while (<IN>) {
		$line++;

		if ( $f =~ /\.s$/ )
		{

			f( '"[^"]+"', "str" );
			f( "'[^']+'", "lit" );
			f( '\.(long|byte|word|space|asci[iz])', 'data' );

			# memref
			s@\[([^\]]+)\]@memref($1)@e;

			# tokens
			f( '[,;\+\-\[\]\*]', 't' );
			f( '(?<=[\s,])(offset|ptr|d?word|byte)\b', 't' );
			f( '(?<![\'"])#(?![\'"]).*$', "comment" );

			# labels
			f( '[a-zA-Z_][a-zA-Z0-9_]+\$?(?=:)', "glabeldef" );
			f( '(?<=\.global)\s+[a-zA-Z0-9_]+', 'glabeldecl' );
			f( '(?<=call)\s+[a-zA-Z0-9_]+\$?', 'glabelref' );
			f( '\b\d+[fb]\b', "unlabelref" );
			f( '\b\d+:', "unlabeldecl" );

			f( ':', "t" );
		
			# constants
			f( '\b0x[a-fA-F0-9]+\b', "hex" );
			f( '\b0b[01]+\b', "bin" );
			f( '\b\d+\b', "dec" );

			# instructions
			f( '\b(push|pop)[_dw]?\b', 'is');
			f( '\b(jmp|jbe?|jn?[scbz]e?|call|i?retf?|int3?)\b', 'ic' );
			f( '\b(loop|rep)n?z?e?\b', 'il' );

			# registers
			f( '\b(e?[abcd]x|e[sd]i|e[bs]p)\b', "gpr" );
			f( '\b([cdefgs]s)\b', "segr" );
			f( '\bcr[0-9]\b', "cr" );
			f( '\bdr[0-9]\b', "dr" );

			f( '\.(global|struct|include|incbin|if|ifc|ifnc|else|endif|macro|endm|rept|endr|intel_syntax)', "dir" );
			f( '\b_?[[:upper:]]+[a-zA-Z0-9_]+\b', 'const' );
			f( '\.((text|data|code)(32|16)?|section)', 'seg');

			# strip nested formatting
			sanitize_comment();
			sanitize_str();

			# extract labels:
			m@<span class="glabeldef">\s*([^<]+)</span>@ and do {
				push @labels, {line=>$line, name=>$1};
				$_ = "<a name='$1'></a>$_";
			};

			m@<span class="const">\s*([^<]+)</span>\s*=\s*(.*)@ and push @const,
				{line=>$line, name=>$1, value=>$2};
		}
		elsif ( $f =~ /\.pl$/ )
		{
			$_ = htmlentities( $_ );
			f( '"[^"]+"', "str" );
			#sanitize_str();
			f( "'[^']+'", "lit" );
			f( '#.*', "comment" );
			f( "[(){}]", "t" );
			f( '[$%@]', "seg" );
			f( '\b(if|else|ifelse|do|while|for|foreach|map|grep|shift|new|use|sub|push|pop|printf|print|defined|or|and)\b', 'dir' );
			#sanitize_comment();
		}
		else
		{
			$_ = htmlentities( $_ );
		}

		#s@$@<br/>@;
		$out .= $_;
	}
	close IN;
	$out .= "</pre>\n";

	# update references
	@ref = filterref( $file, @ref );
	$VERBOSE and printf "Adding %d label references\n", scalar @labels;
	map {
		push @ref, { file => $file, line=>$_->{line}, name=>$_->{name} };
	}  @labels;

	$out .= list( "Globals", \@labels );
	$out .= list( "Constants", \@const );

	return { file => $_[0], content => $out,
		labels => \@labels, const => \@const };
}
################################################################

sub htmlentities($) { $_=$_[0]; $_=~s/&/&amp;/g; $_ =~ s/</&lt;/g; $_ =~ s/>/&gt;/g; $_};

sub list {
	join('', "<h2>$_[0]</h2>\n<ul>",
		(map { ( "<li>",
			$_->{value}
				? $_->{name}. ' = ' . $_->{value}
				: getref( undef, $_->{name} ),
			"</li>\n" )
		} @{$_[1]}), "</ul>");
}


sub f { s@$_[0]@<span class="$_[1]">$&</span>@g; }

sub memref { '[' .'<span class="memref">'.$_[0].'</span>'. ']' }

sub sanitize_comment {
	s@(<span class="comment">)(.*)(</span>)@$1.strip($2).$3@e;
}

sub sanitize_str {
	s@(<span class="str">")(.*)("</span>)@$1.strip($2).$3@e;
}

sub strip { my $a=$_[0]; $a =~ s@</?span[^>]*>@@g; $a }
