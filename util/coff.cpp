#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h> // exit
#include <string.h>
#include <errno.h>


struct filehdr {
unsigned short  h_magic;        /* magic number */
unsigned short  h_nsections;        /* number of sections */
long            h_timdat;       /* time & date stamp */
long            h_symptr;       /* file pointer to symbolic header */
long            h_nsyms;        /* sizeof(symbolic hdr) */
unsigned short  h_opthdr;       /* sizeof(optional hdr) */
unsigned short  h_flags;        /* flags */
};

#define  MIPSELMAGIC    0x0162

#define OMAGIC  0407
#define SOMAGIC 0x0701

typedef struct aouthdr {
short   magic;          /* see above                            */
short   vstamp;         /* version stamp                        */
long    tsize;          /* text size in bytes, padded to DW bdry*/
long    dsize;          /* initialized data "  "                */
long    bsize;          /* uninitialized data "   "             */
long    entry;          /* entry pt.                            */
long    text_start;     /* base of text used for this file      */
long    data_start;     /* base of data used for this file      */
long    bss_start;      /* base of bss used for this file       */
long    gprmask;        /* general purpose register mask        */
long    cprmask[4];     /* co-processor register masks          */
long    gp_value;       /* the gp value used for this object    */
} AOUTHDR;
#define AOUTHSZ sizeof(AOUTHDR)


struct sectionhdr {
char            s_name[8];      /* section name */
long            s_paddr;        /* physical address, aliased s_nlib */
long            s_vaddr;        /* virtual address */
long            s_size;         /* section size */
long            s_sectionptr;       /* file ptr to raw data for section */
long            s_relptr;       /* file ptr to relocation */
long            s_lnnoptr;      /* file ptr to gp histogram */
unsigned short  s_nreloc;       /* number of relocation entries */
unsigned short  s_nlnno;        /* number of gp histogram entries */
long            s_flags;        /* flags */
};


void error( const char * msg )
{
	if (errno)
		perror( msg );
	else
		printf( msg );
	exit(1);
}

const char * getname( char * sname, struct filehdr * h )
{
	if ( sname[0] == '/' )
	{
		return (char*)h + h->h_symptr + h->h_nsyms * 18 + atoi( sname+1 );
	}
	return sname;
}

void print_usage( char ** argv )
{
	printf( "usage: %s [-v] <filename.o> [command [options]]\n", argv[0]);
	printf( "  -v: verbose\n\n");
	printf( "  commands:\n"
			"      --remove-padding <sectionname> <elementsize>\n"
			"        treats <sectionname> as an array containing multiple elements of\n"
			"        <elementsize> and removes trailing padding by updating the section size.\n"
			"        This allows to split structured arrays over multiple object files.\n\n"
//			"      --section-align <sectionname> <elementsize>\n"
	);
}

int main(int argc, char ** argv)
{
	if ( argc < 2)
	{
		print_usage( argv );
		error("no filename");
	}

	bool verbose = 0;
	char * objfilename = NULL;

	char * rempad_sections[10];
	int rempad_elsize[10];
	int rempad_idx=0;

	for ( int i = 1; i < argc; i++ )
	{
		if ( objfilename == NULL )
		{
			if ( argv[i][0] == '-' )
			{
				if ( strcmp( argv[i], "-v" )==0 )
					verbose=1;
				else
					printf( "unknown option: %s\n", argv[i] );
					print_usage( argv );
					exit(1);
			}
			else
				objfilename = argv[i];
		}
		else
		{
			if ( strcmp( "--remove-padding", argv[i] ) == 0 )
			{
				if ( rempad_idx == 9 ) error( "array too small - edit source" );
				if ( i+2 >= argc ) error( "--remove-padding takes <sectionname> <elementsize>" );

				char * n = rempad_sections[rempad_idx]=argv[++i];
				int s = rempad_elsize[rempad_idx]=atoi(argv[++i]);
				if ( verbose )
					printf(" * remove padding from array section %s element size %d\n",
						n, s );

				rempad_idx++;
			}
			else
			{
				printf( "unknown argument: %s\n", argv[i] );
				print_usage( argv );
				exit(1);
			}
		}
	}

	int handle;
	handle = open( objfilename, O_RDWR );
	if ( handle <= 0 )
		error( "Cannot open file" );

	long long flen = lseek( handle, 0, SEEK_END );
	lseek( handle, 0, SEEK_SET );

	unsigned char * buf = (unsigned char*) malloc( flen );
	read( handle, buf, flen );


	struct filehdr * h = (struct filehdr*) buf;

	if ( verbose )
	{
		printf("Magic: %04x\n", h->h_magic);
		printf("Sections: %d\n", h->h_nsections );
		printf("Timedate: %d\n", h->h_timdat );
		printf("Symbol Pointer: %x\n", h->h_symptr );
		printf("Number of symbols: %x\n", h->h_nsyms );
		printf("Optional header len: %d\n", h->h_opthdr);
		printf("Flags: %x\n", h->h_flags);
	}

	sectionhdr* sec = (sectionhdr*) (buf + sizeof(filehdr));

	if ( verbose )
		printf("SECTION nr vaddr    size     name         flags\n");
	for ( int i = 0; i < h->h_nsections; i++)
	{
		const char * sname = getname( sec[i].s_name, h );
		if ( verbose )
			printf("section %2d %08x %08x %-12s %08x", i,
				sec[i].s_vaddr,
				sec[i].s_size,
				sname,
				sec[i].s_flags
			);

		for ( int j = 0; j < rempad_idx; j++ )
		{
			if ( strcmp( sname, rempad_sections[j] ) == 0 )
			{
				int mod = sec[i].s_size % 10;
				if ( verbose )
					printf( " padding=%d", mod );
				if ( mod != 0 )
				{
					int newsize = sec[i].s_size - mod;
					if ( verbose )
						printf(": new size := 0x%x\n", newsize );
					lseek( handle, (unsigned char*)&(sec[i].s_size) - buf, SEEK_SET );
					write( handle, &newsize, 4 );
					// also update section alignment
					lseek( handle, (unsigned char*)&(sec[i].s_flags) - buf, SEEK_SET );
					int newflags = sec[i].s_flags;
					newflags &=~0x00f00000;	// mask out section align flags
					newflags |= 0x00100000; // 1 byte alignment (NOPAD=8 is deprecated).
					write( handle, &newflags, 4);
					if ( verbose )
						printf("newflags:%08x",newflags);
				}
			}
		}

		if ( verbose )
			printf("\n");
	}

	close( handle );

	//struct aouthdr * h = (struct aouthdr*) buf;
}
