#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h> // exit
#include <string.h>

void error( char * msg )
{
	perror( msg );
	exit(1);
}

const char * voltypes[256];

// print ascii
void pa( const char * label, unsigned char * buf, int start, int end )
{
	printf( "%s: (%d) \"", label, 1+ end - start );
	for ( int i = start; i <= end; i ++)
		printf( "%c", buf[i] );
	printf( "\"\n" );
}

void pd( const char * label, unsigned char * buf, int start, int end )
{
	pa( label, buf, start, end );
}

long pn( const char * label, unsigned char * buf, int start, int end )
{
	long value = 0;

	if ( label ) printf( "%s: ", label );

	if ( 1+ end - start == 8 )
	{
		if ( label ) printf( "[" );
		for ( int i = 0; i < 8; i ++ )
		{
			if ( label ) printf( "%02x ", buf[start] );
			value <<= 8; value |= buf[start++]; 
		}
		if ( label ) printf( "] " );
		value &= 0xffffffff;
		//value = *(long*)(&buf[start]);
	}
	else if ( 1+ end - start == 4 )
	{
		if ( label ) printf( "[" );
		for ( int i = 0; i < 4; i ++ )
		{
			if ( label ) printf( "%02x ", buf[start] );
			value <<= 8; value |= buf[start++]; 
		}
		if ( label ) printf( "] " );

		value &= 0xffff;
		//value = *(int*)(&buf[start]);
	}
	else { printf("Illegal numerical length: %d\n", 1 + end - start ); }

	if ( label ) printf( "%d (0x%x)\n", value, value );
	return value;
}

long pnlsb( const char * label, unsigned char * buf, int start, int end )
{
	long value = 0;
	int len = 1+end-start;
	if ( label ) printf( "%s: [", label );
	for ( int i = 0; i < len; i ++)
	{
		if ( label ) printf( "%02lx ", buf[start+i] );
		value <<=8; value |= buf[end-i];
	}
	if ( label ) printf("] %ld (0x%lx)\n", value, value );

	return value;
}

long pnmsb( const char * label, unsigned char * buf, int start, int end )
{
	long value = 0;
	int len = 1+end-start;
	printf( "%s: [", label );
	for ( int i = 0; i < len; i ++)
	{
		printf( "%02lx ", buf[start+i] );
		value <<=8; value |= buf[start+i];
	}
	printf("] %ld (0x%lx)\n", value, value );

	return value;
}

// print directory record
void pdr( const char * label, unsigned char * buf, int start, int end )
{
	printf( "%s: ", label);

	printf( "  Directory Record Length: %d (0x%x)\n", buf[start], buf[start] );
	printf( "  Extended Attribute Length: %d (0x%x)\n", buf[start+1], buf[start+1] );
	pn( "  Location of Extent", buf, start+2, start + 9 );
	pn( "  Data Length", buf, start+10, start + 17 );
	pa( "  Recording Date and Time", buf, start+18, start + 24 );
	printf( "  File Flags: %x\n", buf[start+25] );
	printf( "  File Unit Size: %d\n", buf[26] );
	printf( "  Interleave Gap Size: %d\n", buf[27] );
	pn( "  Volume Sequence Number", buf, start+28, start+31);
	printf( "  Length of file identifier: %d\n", buf[start+32]);
	pa( "  File Identifier", buf, start+33, start+32+buf[start+32]);
	// padding byte if buf[start+32] is odd
	// buf[start] - LEN_SU +1 ... buf[start] system use bytes

	printf("\n");
}

unsigned char buf[2048];
int handle;
int sector;
void load_sector( int sect )
{
	lseek( handle, 2048 * sector, SEEK_SET );
	read( handle, buf, 2048 );
	sector = sect;
	printf( "\n== Sector %d (0x%x) offset %x\n", sect, sect, 2048 * sect );
}

inline bool is_rr( const char * sig, unsigned char * buf, int offs )
{
	return ( buf[offs] == sig[0] && buf[offs+1] == sig[1] && buf[offs+2] >= 4
	//	&& buf[3] == 1
	);
}

int main(int argc, char ** argv)
{

	voltypes[0] = "Boot Record";
	voltypes[1] = "Primary Volume Descriptor";
	voltypes[2] = "Supplementary/Enhanced Volume Descriptor";
	voltypes[3] = "Volume Partition Descriptor";
	voltypes[255] = "Volume Descriptor Set Terminator";
	for ( int i = 4; i < 255; i ++ ) voltypes[i] = "reserved";


	handle = open( "os.iso", O_RDONLY );
	if ( handle <= 0 )
		error( "Cannot open file" );

	sector = -1;
	for ( int i = 0; i < 16; i ++)
	{
		read( handle, buf, 2048 );
		sector++;

		for ( int j = 0; j < 2048; j ++)
		{
			if ( buf[j] )
				printf ("System data: sector %d offset 0x%x: %x\n",
					i, j, buf[j] );
		}
	}

	long path_sector;
	long boot_catalog_sector;

	for ( int r = 0; r < 10 && buf[0] != 255; r ++ )
	{
	// read volume descriptor (sector 16)
	read( handle, buf, 2048 );
	sector++;
	printf("\nsector %d\n", sector );


	printf( "Volume Descriptor Type: %d (%s)\n", buf[0], voltypes[buf[0]] );
	printf( "Standard Identifier: %c%c%c%c%c\n",
		buf[1], buf[2], buf[3], buf[4], buf[5] );
	printf( "Volume Descriptor Version: %d\n", buf[6] );

	if ( buf[0] == 0 ) // boot record
	{
		// 7..38: boot system identifier (ascii)
		// 39..70: boot identifier (ascii)
		// 71..2047: boot system use 
		pa( "Boot System Identifier", buf, 7, 38 );
		pa( "Boot Identifier", buf, 39, 70 );
		pd( "Boot System Use", buf, 71, 128 );

		const char * eltorito = "EL TORITO SPECIFICATION";
		//bool ok = true;
		//for ( int q = 0; q < strlen( eltorito ); q++ )
		//	if ( eltorito[q] != buf[7 + q] ) {ok = false; break;}
		if ( memcmp( &buf[7], eltorito, strlen( eltorito ) ) == 0 )
		{
			boot_catalog_sector = 
			pnlsb( "Boot Catalog", buf, 0x47, 0x4a );
		}
	}
	else if ( buf[0] == 1 ) // primary volume desc
	{
		// offset 7: unused
		// 9 to 40
		pa( "System Identifier", buf, 8, 39 );	// for sectors 0..15
		pd( "Volume Identifier", buf, 40, 71 );
		// 72-79 unused
		pn( "Volume Space Size", buf, 80, 87 );
		// 88-119 unused
		pn( "Volume Set Size", buf, 120, 123 );
		pn( "Volume Sequence Number", buf, 124, 127 );
		pn( "Logical Block Size", buf, 128, 131 );
		pn( "Path table size", buf, 132, 139 );
		path_sector = 
		pnlsb( "LSB Path Table location: ", buf, 140, 143 );
		pnlsb( "LSB Path Table optional location: ", buf, 144, 147 );
		pnmsb( "MSB Path Table location: ", buf, 148, 151 );
		pnmsb( "MSB Path Table optional location: ", buf, 152, 155 );
		pdr( "Directory Record for root directory", buf, 156, 189 );
		for ( int i = 156; i <= 189; i ++ ) printf("%c (%02x) ", buf[i], buf[i]);
		printf("\n");
		pd( "Volume Set Identifier", buf, 190, 317 );
		pa( "Publisher Identifier", buf, 318, 445 );
		pa( "Data Preparer Identifier", buf, 446, 573 );
		pa( "Application Identifier", buf, 574, 701 );
		pd( "Copyright File Identifier", buf, 702, 738 ); // d-char,sep1, sep2
		pd( "Abstract file Identifier", buf, 739, 775 ); // d-, sep1, sep2
		pd( "Bibliographic File identifier", buf, 776, 812 ); // d-, sep1, sep2
		
		pa( "Volume Creation date and time", buf, 813, 829 ); // digits/numval
		pa( "Volume Modification date and time", buf, 830, 846 ); // digits/numval
		pa( "Volume Expiration date and time", buf, 847, 863 ); // digits/numval
		pa( "Volume Effective date and time", buf, 864, 880 ); // digits/numval
		printf( "File Structure Version: %d\n", buf[881] );
		// 882 reserved

		// app use: 883..1394
		pa( "Application Use", buf, 883, 1394 );
		pa( "Reserved", buf, 1395, 2047 );
	}
	else
	{
		printf(" no details for volume type %d\n", buf[0]);
	}

	}

	if ( boot_catalog_sector )
	{
		lseek( handle, 2048 * boot_catalog_sector, SEEK_SET );
		read( handle, buf, 2048 );
		sector = path_sector;

		//read( handle, buf, 2048 ); sector++;
		printf( "\nsector %d\nBoot Volume:\n", sector );

		int cksum = 0;
		for ( int i = 0; i < 0x20; i+=2 )
			cksum += (buf[i] | (buf[i+1]<<8));

		//if ( cksum == 0 && buf[0] == 1 )
		{
			printf( "Validation Entry" );
			// Validation Entry (type 1 )
			printf( "  Header ID: %d\n", buf[0] );
			printf( "  Platform ID: %d (%s)\n", buf[1],
				buf[1] == 0 ? "80x86" :
				buf[1] == 1 ? "PowerPC" :
				buf[1] == 2 ? "Mac" : "unknown"
			);
			printf( "  Checksum: %04x (%04x)\n", (buf[0x1c] | (buf[0x1d]<<8)), cksum );
			printf( "  Key Bytes: %02x %02x\n", buf[0x1e], buf[0x1f] );

			int offset = 0x20;

			printf( "\nInitial/Default entry\n" );
			printf( "  Boot Indicator: %02x (%s)\n", buf[offset+0], 
				buf[offset] == 0 ? "Not Bootable" :
				buf[offset] == 0x88 ? "Bootable" : "unknown"
			);
			int t = buf[offset+1];
			printf( "  Boot Emulation Type: %d (%s)\n", t,
				t == 0 ? "No Emulation" :
				t == 1 ? "1.2M Disk" :
				t == 2 ? "1.44M Disk" :
				t == 3 ? "2.88M Disk" :
				t == 4 ? "HDD" : "unknown"
			);

			printf( "  Load Segment: %04x\n", buf[offset+2] | (buf[offset+3]<<8) );
			// same as byte 5 of partition table in boot image
			pnlsb( "  System Type", buf, offset+4, offset+5 );
			pnlsb( "  Sector Count", buf, offset+6, offset+7 );
			pnlsb( "  Relative Block Address", buf, offset+8, offset+0xb );

			offset += 0x20;

			if ( buf[offset] == 0x90 || buf[offset]==0x91 )
			{
			printf( "\nSection Header Entry\n" );
			printf( "  HEader Indicator: %02x", buf[offset] );
			}
		}
	}

	if ( path_sector )
	{
		printf("\nPath Sector: %d (0x%02x) offs %x\n", path_sector,
			path_sector, path_sector * 2048);

		load_sector( path_sector );
/*
		while ( sector < path_sector )
		{
			read( handle, buf, 2048 ); sector++;
		}

		if ( sector == path_sector )
*/
		{
			printf( "\nsector %d\n", sector );

			if (false)
			for ( int i = 0; i < 2048; i ++)
			{
				if ( i % 8 == 0 )
				{
					printf( "\n%04x: ", i );
				}
				printf( "%02x (%c)", buf[i], buf[i] );
			}

			int offs = 0;

			unsigned char extbuf[ 2048 ];

			while ( buf[offs] != 0 )
			{
			printf( "Path Table Record: OFFS: %d (0x%x)\n", offs, offs);
			printf( "  Directory Identifier len: %d\n", buf[offs+0] );
			printf( "  Extended Attribute Record len: %d\n", buf[offs+1] );
			int extsect=
			pnlsb( "  Location of extent", buf, offs+2, offs+5);
			pnlsb( "  Parent directory number", buf, offs+6,offs+7);
			pd( "  Directory Identifier", buf, offs+8, offs+7+buf[offs+0] );

			offs += 8 + buf[offs] + (buf[offs]&1);

			if ( extsect )
			{
				lseek( handle, extsect * 2048, SEEK_SET );
				read( handle, extbuf, 2048 );
				printf( "   - sector %d (0x%x) offset 0x%x\n", extsect, extsect,
					extsect * 2048 );

				int o = 0;
				while ( o < 2048 )
				{
					if ( extbuf[o] == 0 ) break;

					//pdr( "   Directory Record", extbuf, o, o + extbuf[o] );
					printf("    [offset: %x]\n", o);
					printf("    File:(%d) \"", extbuf[o+32] );
					for ( int j = 0; j < extbuf[o+32]; j ++)
						printf( "%c", extbuf[o+33+j] );
					printf( "\" FUS 0x%x", extbuf[o+26] ); // file unit size
					printf( " ExtAttrLen: %d", extbuf[o+1] );
					printf( " Flags: 0x%02x", extbuf[o+25] );
					printf( " Vol %d", pn(NULL, extbuf, 28, 31 ));
					int fext = pn( NULL, extbuf, o+2, o+9 );
					int size = pn( NULL, extbuf, o+10, o+17 );
					printf( "EXT %02x Size %d\n", fext, size );
					printf("      rlen %d nmlen %d extradatalen: %d",
						extbuf[o], extbuf[o+32],
						extbuf[o] - 33 - extbuf[o+32]
					);
					int flags = extbuf[o+25];
					printf( " F(%02x):", flags );
					if ( flags & 1 ) printf("Hidden ");
					if ( flags & 2 ) printf("Directory ");
					if ( flags & 4 ) printf("Associated ");
					if ( flags & 8 ) printf("Record ");
					if ( flags & 16) printf("Protection "); // permissions
					if ( flags & 128) printf("NonFinalRecord ");
					printf("\n");
					int start = o+33+extbuf[o+32];// + (extbuf[o+32]&1);
					if ( start & 1 ) start ++;
					printf( "      System Use: %d .. %d", start, o+extbuf[o] );
					// RockRidge extensions:
					for ( int p = start; p < o+extbuf[o]; )
					{
						printf( "\n      %3d: %c%c: len %3d v%d - ", p, extbuf[p], extbuf[p+1], extbuf[p+2], extbuf[p+3] );

						// SUSP fields:
						if ( is_rr( "SP", extbuf, p ) )
						{
							printf("Check: %02x%02x", extbuf[p+4], extbuf[p+5]);
							printf(" skip: %d", extbuf[p+5]);
						}
						else if ( is_rr( "CE", extbuf, p ) )
						{
							printf( "Continuation Area LBA 0x%x",
								pn( NULL, extbuf, p+4, p+11 ) );
							printf( " offset 0x%x", pn( NULL, extbuf, p+12, p+19 ) );
							printf( " length %d", pn(NULL, extbuf, p+20, p+27) );
						}
						else
						// RockRidge fields:
						if ( is_rr( "PX", extbuf, p ) )
						{
							printf("POSIX permissions: %o", pn( NULL, extbuf, p+4, p+4+7 ) );
							printf( " link %d", pn( NULL, extbuf, p+12, p+19) );
							printf( " uid %d", pn( NULL, extbuf, p+20, p+27) );
							printf( " gid %d", pn( NULL, extbuf, p+28, p+35) );
							if ( extbuf[p+2] > 36 )
							printf( " ino %d", pn( NULL, extbuf, p+36, p+43) );

						}
						else if ( is_rr( "TF", extbuf, p ) )
						{
							printf("Timestamps: Flags: 0x%x - ", extbuf[p+4] );
							int fl = extbuf[p+4];
							int fieldlen = fl & 128 == 0 ? 7 : 17;
							int o = p+5;
							if ( fl & 1 ) { printf("Creation " ); o+=fieldlen; }
							if ( fl & 2 ) { printf("Modify " ); o+=fieldlen; }
							if ( fl & 4 ) { printf("Access " ); o+=fieldlen; }
							if ( fl & 8 ) { printf("Attributes " ); o+=fieldlen; }
							if ( fl & 16 ) { printf("Backup " ); o+=fieldlen; }
							if ( fl & 32 ) { printf("Expiration " ); o+=fieldlen; }
							if ( fl & 64 ) { printf("Effective " ); o+=fieldlen; }
						}
						else
						{
						for ( int pp = p+4; pp < p + extbuf[p+2]; pp++ )
							printf("%02x ", extbuf[pp] );
						printf("\"");
						for ( int pp = p+4; pp < p + extbuf[p+2]; pp++ )
							printf("%c", extbuf[pp] );
						printf("\"");
						}

						int p2 = p + extbuf[p+2];

						if ( p2 + 4 > o+extbuf[o] ) break;

						if ( p2 <= p ) { printf("ERROR: len field <=0: p=%d next=%d len=%d", p, p2, extbuf[p+2]);break;}
						p=p2;


						//p += extbuf[p+2] -1;
					}
						printf("\n");

					// TODO: read file extent - is it data or permissions etc

					/*
					//pa("    File: ", extbuf, o+33, o+32+extbuf[o+32] );
				
				printf("\n    Directory Record:\n");
				printf( "    Directory Record len: %d\n", extbuf[o+0] );
				printf( "    Extended Attribute len: %d\n", extbuf[o+1] );
				pn( "    Extent", extbuf, o+2, o+9 );
				pn( "    Size", extbuf, o+10, o+17 );
				pa( "    Date", extbuf, o+18, o+24 );
				printf( "    Flags: 0x%02x\n", extbuf[o+25] );
				printf( "    File Unit Size: %d\n", extbuf[o+26] );
				printf( "    Interleave: %d\n", extbuf[o+27] );
				pn( "    Volume Sequence Number", extbuf, o+28, o+31 );
				printf( "    Name Len: %d\n", extbuf[o+32] );
				pa( "     Name", extbuf, 33, 33+extbuf[o+32] );
				//o += 33 + extbuf[o+32];
				*/
				o+=extbuf[o];
				}
			}


			printf("\n");
			}

			printf("End of path table at offset %d (0x%x)\n", offs, offs );
			
			
		}
	}

}
