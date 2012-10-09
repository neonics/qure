#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h> // exit
#include <string.h>

unsigned char * buf;
int handle;

int main(int argc, char ** argv)
{
	if ( argc != 2 ) { printf( "usage: %s <kernel.sym>\n", argv[0]); exit(1); }
	printf( "loading '%s' ", argv[1] );
	handle = open( argv[1], O_RDONLY );
	if ( handle <= 0 ) { perror( "Cannot open file" ); exit(2); }
	long long size = lseek( handle, 0, SEEK_END );
	lseek( handle, 0, SEEK_SET );
	printf( "size: %d\n", size );
	buf = (unsigned char*)malloc( size );
	if ( buf <= 0 ) { perror( "alloc buffer" ); exit(3); }

	if ( read( handle, buf, size ) != size ) { perror("read");exit(4);}

	int * ptr = (int *) buf;
	int numentries = *ptr++;
	buf += sizeof(int) + 2 * numentries * sizeof(int);
	printf( "numentries: %d\n", numentries);

	for ( int i = 0; i < numentries; i ++)
	{
		printf("%08x: %08x %s\n", ptr[i], ptr[i+numentries],buf+ptr[i+numentries] );
	}
}
