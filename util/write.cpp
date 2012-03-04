/**
 * Creates a zero-filled file of given length, marking the first sector
 * as a bootsector, optionally overlaying a bootsector file that may
 * be longer than 512 bytes.
 */

#include <sys/types.h> /* unistd.h needs this */
#include <unistd.h>    /* contains read/write */
#include <fcntl.h>
#include <string.h> // memset
#include <stdio.h> // printf, fopen



char * out_name = NULL;
char * boot_name = NULL;
bool parse_args( int argc, char ** argv);


char boot_buf[512];
int h_out, h_in = -1;
int out_offs = 0;
int sector = 0;
int outlen = 144 * 10240;

int next()
{
	memset(boot_buf, 0, 512);

	if ( h_in >= 0 )
	{
		int rd = read(h_in, boot_buf, 512);
		//printf( "Read %d bytes from %s\n", rd, boot_name );
		if ( rd < 512 )
		{
			close( h_in );
			h_in = -1;
		}
	}

	if ( sector++ == 0 )
	{
		boot_buf[510] = 0x55;
		boot_buf[511] = 0xaa;
	}

	return sector * 512 <= outlen;
}

int main( int argc, char * argv[] )
{
	if ( !parse_args( argc, argv ) )
		return 1;
	
	printf("Creating image %s\n", out_name );


        h_out = open( out_name, O_RDWR|O_CREAT|O_BINARY);
	printf("Opened %s, handle %d\n", out_name, h_out );

 	if ( boot_name )
	{
		printf("Reading boot image: %s\n", boot_name );
		h_in = open( boot_name, O_RDONLY );
		if ( h_in <= 0 )
		{
			printf( "not found: %a\n", boot_name );
			return 1;
		}
		int flen = lseek( h_in, 0, SEEK_END );
		if ( flen > 512 )
		{
			printf( "Warning: image larger than bootsector (512): %d bytes (%d sectors)\n", flen, flen >> 9 + (flen &0x1ff>0) );
		}
		
		lseek( h_in, 0, SEEK_SET );
	}

	while ( next() )
	{
		out_offs += write(h_out, boot_buf, 512);
	}

        close(h_out);

	return 0;
}

bool parse_args( int argc, char ** argv )
{
	bool ok = true;
	for ( int i = 1; ok && i < argc; i ++ )
	{
		if ( strcmp( argv[i], "-b" ) == 0 )
		{
			if ( ++i < argc ) boot_name = argv[i];
			else ok = false;
		}
		else if ( strcmp( argv[i], "-o" ) == 0 )
		{
			if ( ++i < argc ) out_name = argv[i];
			else ok = false;
		}
		else ok = false;
	}

	if ( !ok || out_name == NULL )
	{
		printf( "Missing out-image-filename\n\n"
			"Usage: %s [-b boot.bin] -o <outfile.img>\n\n"
			"Write a 1.44MB floppy disk image, optionally\n"
			"overlaying a bootsector. It marks the sector\n"
			"as a boot sector: sector[510] = 55AA\n",
			argv[0] );
		return false;
	}

	return true;
}
