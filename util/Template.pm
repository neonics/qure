#!/usr/bin/perl

# this file works together with util/template.html
# and web/www.neonics.com/js/template.js

package Template;
use FindBin;

sub new {
	bless {
		xml	=> undef,
		relpath	=> "",
		templatefile=> 'default',
		menuxml	=> undef,
		title	=> "",
		tagline	=> undef,#"Conscious Computing",
		styles	=> [],
		css	=> []
	}, ref($_[0]) || $_[0];
}

sub usage {
	print <<EOF;

	-t <t>		template file to use. Specify 'none' for a minimal
			HTML5 wrapper; 'default' for the builtin template.html.
	--template <t>	alias for -t
	--css <uri>	add custom css
	-x <xml>	specify dynamic XML content URI to load at runtime.
	-s <s>		specify XSL stylesheet; more than one allowed.
	--cid <cid>	specify element ID to receive dynamic content
	-p <p>		relative path to css/, js/, img/, style/ paths.
	--relpath <p>	alias for -p.
	--onload <str>	append <str> to the javascript onload handler.
	--menuxml <xml>	specifies a menu.xml file to load using AJAX.
	--title	<t>	specify title.
	--rawtitle <t>	idem; transform "dir/some_file.(txt|html) -> Some File.
	--tagline <t>	specify a tagline.
	--toc		generate a TOC using all <h[123456]> tags.
EOF
}

sub args {
	my ( $self, @args ) = @_;

	while ( $args[0] =~ /^-./ )
	{
		my $a = shift @args;
		$a eq '-t' || $a eq '--template'
			and do { $self->{templatefile} = shift @args;1 } or
		$a eq '--css' and do { push $self->{css}, shift @args or die "--css requires argument" } or
		$a eq '-x' and do { $self->{xml} = shift @args;1} or
		$a eq '-s' and do { push $self->{styles}, shift @args;1} or
		$a eq '--cid' and do { $self->{cid} = shift @args;1 } or
		$a eq '-p' || $a eq '--relpath' and do { $self->{relpath} = shift @args;1} or
		$a eq '--onload' and do { $self->{onload} = shift @args;1} or
		$a eq '--menuxml' and do { $self->{menuxml} = shift @args; 1} or
		$a eq '--title' and do { $self->{title} = shift @args;1} or
		$a eq '--rawtitle' and do {
			my $title=shift @args;
			$title =~ s@^.*?/@@g;   # strip root of path
			$title =~ s/\.(txt|html)$//;    # strip suffix
			$title =~ tr/_/ /;
			$title =~ s/([[:lower:]])([[:upper:]])/\1 \2/g;
			$self->{title}=$title;
			1;
		} or
		$a eq '--tagline' and do { $self->{tagline} = shift @args;1} or
		$a eq '--toc' and do { $self->{toc}=1 } or
		die "unknown option: $a";
	}


	$self->{template} = $self->{templatefile} eq 'default'
		? readfile( $FindBin::Bin."/template.html" )
		: $self->{templatefile} ne 'none'
			? readfile( $self->{templatefile} )
			: <<'EOF';
<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
${CSS}
    <title>${TITLE}</title>
  </head>
  <body>
<h1>${TITLE}</h1>
${TOC}
${CONTENT}
  </body>
</html>
EOF

	$self->{onload} = sprintf( "template( %s, '%s', [%s], %s, %s); %s",
		defined($self->{xml}) ? "'$self->{xml}'" : "null",
		$self->{relpath},
		join(',', map{ "'$_'"} @{$self->{styles}}),
		defined $self->{menuxml} ? "'$self->{menuxml}'" : "null",
		defined $self->{cid} ? "'$self->{cid}'" : "null",
		$self->{onload}
	)
	#"template( $xml, '$relpath', [".join(",", map{ "'$_'"} @styles)."]"
	#	.(defined $menuxml ? ", '$menuxml'" : "")
	#	."); $onload"
	unless $self->{onload};

	#print "DUMP:\n"; map { print "$_: $self->{$_}\n" } keys %$self;

	$self->{args} = \@args;
	@args;
}

sub process {
	my ($self, $content, $overrides) = @_;

	my %opts = %$self;

	defined $overrides and
		map { $opts{$_} = $overrides->{$_} } keys %$overrides;

	$opts{toc} and $opts{toc} = gentoc( $content );

	$self->{content} = $opts{template};

	$self->_fill( "CONTENT",$content );
	$self->_fill( "TOC",	$opts{toc} );
	$self->_fill( "ONLOAD",	$opts{onload} );
	$self->_fill( "RP",	$opts{relpath} );
	$self->_fill( "TITLE",	$opts{title} );
	$self->_fill( "TAGLINE",$opts{tagline} );
	$self->_fill( "CSS",    join("\n",
		map { "    <link rel='stylesheet' type='text/css' href='$opts{relpath}$_'/>" }
		@{$opts{css}} )
	);

	$self->{content};
}


# Replaces tags:
#  ${TAG}
#  ${TAG|default value}
sub _fill {
	my ($self, $tag, $val) = @_;
	$self->{content} =~ s/\$\{$tag(\|([^\}]*))?\}/$val||$2/ge;
}



##############################################################################
# Utility functions

sub gentoc {
	# generate a TOC:
	my $tmp = $_[0];
	my $o="";
	my $id=0;
	my @toc;
	while ( $tmp =~ /<h(.)>(.*?)<\/h\1>/ )
	{
		push @toc, {link=>"<a href='#toc$id'>$2</a>", level=>$1};
		$tmp = $';
	#	$_ = $&; s/<h(.)>/<h\1 id='toc$id'>/; $o.=$_;
		$o.=$` . "<a name='toc$id'></a>" . $&;
		$id++;
	}

	$c = $o . $tmp;

	my $toc;
	if ( scalar @toc ) {
		my $lev=0;
		$toc = "<h2 class='toc'>TOC</h2>\n";
		foreach ( @toc ) {
			while ( $_->{level} < $lev )
			{
				$lev --;
				$toc .= "</ol>";
			}
			while ( $_->{level} > $lev )
			{
				$lev ++;
				$toc .= "<ol>";
			}

			$toc .= "<li>$_->{link}</li>\n";
		}
		while ( $lev-- > 0 )
		{
			$toc .= "</ol>";
		}
	}
	$toc;
}


sub readfile {
	open IN, $_[0] or die "can't find template file $_[0]: $!";
	my @c = <IN>;
	close IN;
	join( '', @c);
}

1;
