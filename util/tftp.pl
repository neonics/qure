#!/usr/bin/perl

use Socket;

my $phost = $ARGV[0] or die "expect hostname";#"192.168.1.27")
$naddr = inet_aton($phost) or die "invalid address: $!";
$addr = sockaddr_in(69, $naddr) or die "can't create address: $!";

socket( SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp") ) or die $!;

# send request
my $msg = pack 'n', 1;	# READ
$msg .= "/boot.img\0octet\0";
send( SOCKET, $msg, 0, $addr ) or die $!;
print "Sent request\n";
$addr = undef;	# reset address: server changes port; see below.

$blocksize=512;
$indata = "";
$total_datalen = 0;
my ($opcode,$blocknr,@data) = undef;
open OUT, ">:raw", "tftp.out";
do {
	defined( $peer_addr = recv( SOCKET, $indata, 1518, 0 )) or die "recv: $!";
	defined( $addr ) or $addr = sockaddr_in( (sockaddr_in($peer_addr))[0], $naddr );

	( $opcode, $blocknr, @data ) = unpack 'nnC*', $indata;
	if ( $opcode == 3 )
	{
		$total_datalen += scalar(@data);
		print OUT pack('C*', @data);
	}
	printf "RX %d bytes; op: %d, block %d, datalen %d (total %d)\n",
		length( $indata ), $opcode, $blocknr, scalar(@data), $total_datalen;
	send( SOCKET, pack("nn", 4, $blocknr), 0, $addr ) or die "send: $!";

} while ( $opcode == 3 && scalar(@data) == $blocksize );
close OUT;
