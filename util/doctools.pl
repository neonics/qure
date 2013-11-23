#!/usr/bin/perl

%options = (
	dir	=> '.',
	type	=> 'txt'
);

while ( $ARGV[0] =~ /^-/ )
{
	my $opt = shift @ARGV;

	$opt eq '-d' and $options{dir} = shift @ARGV || die "$opt: expect value" or
	$opt eq '-t' and $options{type} = shift @ARGV || die "$opt: expect value"
	or die "unknown option: $opt";
}

grep { $_ eq $options{type} } qw/txt html/ or die "unknown type: $options{type}";
$options{dir}=~s@/$@@;

my $command = shift @ARGV;

$command eq 'list' and do {
	print process_index(
		-f $options{dir}."/.index"
		? `cat $options{dir}/.index`
		: map {	s/^$options{dir}\///; $_ } `ls $options{dir}/*.$options{type}`
	);
} or die "unknown command: $command";


sub process_index {
	@_ = grep { ! /^\s*#/ } @_;	# no comment
	@_ = map { s/#.*$//; $_ } @_;
	@_ = map { s/^\s+|\s+$//; $_ } @_;
	@_ = map { s/\s*$/\n/; $_ } @_;
	@_ = grep { /\.$options{type}$/ } @_;
	@_ = grep { my $a=$_; chomp $a; -f $options{dir}."/".$a
		or do { warn "WARNING: missing $options{dir}/$_"; 0} } @_;
	@_ = map { s/\.$options{type}$//; $_ } @_;
}
