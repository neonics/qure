#!/usr/bin/perl

use Socket;

my $addr = $ARGV[0] or die "expect hostname";#"192.168.1.27")
$addr = inet_aton($addr) or die "invalid address: $!";
$addr = sockaddr_in(4000, $addr) or die "can't create address: $!";

socket( SOCKET, PF_INET, SOCK_DGRAM, getprotobyname("udp") ) or die $!;

my $msg = 'flood test' . ( ' ' x 1000 );
print "Message: [$msg]\n";

for ( $i=0; $i<3000; $i++) {
send( SOCKET, $msg, 0, $addr ) or die $!;
}
