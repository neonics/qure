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
#include <stdlib.h> // atoi

// C++ stuff missing in C:
#ifndef bool
  typedef unsigned char bool;
#endif
#ifndef false
# define false 0
# define true 1
#endif
// Cygwin stuff missing in Linux:
#ifndef O_BINARY
# define O_BINARY 0
#endif

int verbose = 0;
bool debug = false;
char * out_name = NULL;
char * boot_name = NULL;
const char * images[] = { 0,0,0,0,0,0,0,0,0,0 }; // a few image pointers...
int imgidx = 0;
int rimgidx = 0;

int dirindex_sector = -1;
long long dirindex_index = 0;

bool parse_args( int argc, char ** argv);

unsigned char boot_buf[512];
int h_out, h_in = -1;
int out_offs = 0;
int sector = 0;
int outlen = 144 * 10240;
bool no_pad = false;

void fill_sector()
{
	if ( h_in < 0 && rimgidx < imgidx && images[rimgidx] != 0 )
	{
//		printf("1 DBG h_in %d rimgidx %d imgidx %d\n", h_in, rimgidx, imgidx );

		if ( images[rimgidx][0] == '*' )
		{
			dirindex_sector = sector;
			dirindex_index = 0;


			sprintf( (char*)boot_buf, "RAMDISK0" );

			if ( verbose )
			printf( " + sector %02d (0x%04x):"
				" add image %d: RAMDISK0 directory index\n",
				sector, sector << 9,
				rimgidx,
				dirindex_sector, dirindex_sector <<9 );

			// since it is one sector, we can mark it as done already:
			rimgidx++;
		}
		else
		{
			if ( verbose )
			printf( " + sector %02d (0x%04x):"
				" add image %d: %s",
				sector, sector << 9,
				rimgidx, images[rimgidx] );

			h_in = open( images[rimgidx], O_RDONLY );

			if ( h_in <= 0 )
			{
				printf( " ERROR: file not found: %s\n", images[rimgidx] );
				exit(1);
			}
			else
			{
				long long flen = lseek( h_in, 0, SEEK_END );
				long sl = (flen >> 9) + (flen % 9 > 0);

				lseek( h_in, 0, SEEK_SET );
				if ( verbose )
				printf( " - %lld bytes in %ld sectors\n",
					flen, (flen + 0x1ff ) >> 9
				);

				if ( dirindex_sector >=0 )
				{
					long long so = ( sector - dirindex_sector ) << 9;
					long ooffs = lseek( h_out, 0, SEEK_CUR );

					if ( verbose )
					printf( " * sector %02d (0x%04x):"
						" update index %lld:"
						" sector %02d (%02lld) + %02d"
						" (0x%04x + 0x%04x)\n",
						dirindex_sector, dirindex_sector << 9,
						dirindex_index, // long long
						sector, so >> 9, sl,
						sector << 9, flen
					);


					// increment ramdisk index counter
					lseek( h_out, (dirindex_sector<<9) + 8, SEEK_SET );
					dirindex_index++;
					write( h_out, &dirindex_index, 8 );
					// write ramdisk directory entry offset and size
					lseek( h_out, (dirindex_index-1) * 16, SEEK_CUR );
					write( h_out, &so, 8 );
					write( h_out, &flen, 8 );

					lseek( h_out, ooffs, SEEK_SET );
				}
			}

		}
	}
	else
	{
		static bool b = true; // once {}
		if ( b && h_in < 0 )
		{
			b=false;
			if ( verbose )
			printf(" . sector %02d (0x%04x): end of images."
				" Total size: %d bytes / %dkb / %.3fMb\n",
				sector, sector << 9,
				(sector<<9), (sector<<9)>>10, ((sector<<9)>>10)/1024.0
			);
		}
	}


	if ( h_in >= 0 )
	{
		int rd = read(h_in, boot_buf, 512);
		//printf( "%d: Read %d bytes from %s\n", sector, rd, boot_name );
		if ( rd < 512 )
		{
			close( h_in );
			h_in = -1;
			rimgidx ++;

			if ( rd == 0 )
				fill_sector();
		}
	}

}


int next()
{
	memset(boot_buf, 0, 512);

	fill_sector();

	if ( sector++ == 0 )
	{
		boot_buf[510] = 0x55;
		boot_buf[511] = 0xaa;
	}

	return no_pad
		? rimgidx < imgidx
		: sector * 512 <= outlen;
}

int main( int argc, char * argv[] )
{
	if ( !parse_args( argc, argv ) )
		return 1;

	if ( verbose )
		printf("Creating image %s\n", out_name );

	h_out = open( out_name, O_RDWR|O_CREAT|O_BINARY);

	while ( next() )
	{
		out_offs += write(h_out, boot_buf, 512);
	}

	if ( verbose )
	printf( " . sector %02d (0x%04x): end of image.\n", sector, sector << 9 );

	close(h_out);

	return 0;
}

bool parse_args( int argc, char ** argv )
{
	bool ok = true;
	int i;

	for ( i = 1; ok && i < argc; i ++ )
	{
		if ( strcmp( argv[i], "-v" ) == 0 )
			verbose++;
		else if ( strcmp( argv[i], "-b" ) == 0 )
		{
			if ( ++i < argc ) images[imgidx++] = argv[i];
			else ok = false;
		}
		else if ( strcmp( argv[i], "-rd" ) == 0 )
		{
			images[imgidx++] = "*";
		}
		else if ( strcmp( argv[i], "-o" ) == 0 )
		{
			if ( ++i < argc ) out_name = argv[i];
			else ok = false;
		}
		else if ( strcmp( argv[i], "-np" ) == 0 )
		{
			no_pad = true;
		}
		else if ( strcmp( argv[i], "-s" ) == 0 )
		{
			if ( ++i < argc && ( outlen = atoi( argv[i] ) ) )
				outlen <<= 9;
			else
				ok = false;
		}
		else
		{
			ok = false;
			printf( "Invalid argument: %s\n", argv[i] );
		}
	}

	if ( debug )
		for ( i = 0; i < imgidx; i ++)
		{
			printf( " - Image '%s'\n", images[i] );
		}

	if ( !ok || out_name == NULL )
	{
		if ( out_name == NULL )
			printf( "Missing out-image-filename\n");
		printf( "\n"
			"Usage: %s [-np] [-b <boot.bin>" /*" [-wa xxxx]"*/"] [-rd] -o <outfile.img>\n\n"
			"Write a 1.44MB floppy disk image, marking the first "
			"sector as a boot sector.\n\n"

			"  -s <sectors>\tspecifies size of output image (default 2880 for 1.44Mb)\n"
			"  -np      \tno pad: do not pad output to 1.44Mb\n"
			"  -b <file>\tappend image at next sector alignment, "
			"starting at 0.\n\n"

			"  -rd      \tadd ramdisk directory index.\n"
			"\t\tThe offset of images specified (with -b) following\n"
			"\t\tthis option will be recorded in the directory index.\n\n"
			,

			argv[0] );
		return false;
	}

	return true;
}
