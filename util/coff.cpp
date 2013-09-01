#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h> // exit
#include <string.h>


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
	perror( msg );
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

int main(int argc, char ** argv)
{
	if ( argc < 2)
	{
		printf( "usage: %s <filename.o> [command [options]]\n", argv[0]);
		printf( "  commands:\n"
				"      --remove-padding <sectionname> <elementsize>\n"
				"        treats <sectionname> as an array containing multiple elements of\n"
				"        <elementsize> and removes trailing padding by updating the section size.\n"
				"        This allows to split structured arrays over multiple object files.\n"
		);
		error("no filename");
	}

	char * rempad_sections[10];
	int rempad_elsize[10];
	int rempad_idx=0;
	for ( int i = 2; i < argc; i++ )
	{
		if ( strcmp( "--remove-padding", argv[i] ) == 0 )
		{
			if ( rempad_idx == 9 ) error( "array too small - edit source" );
			if ( i+2 >= argc ) error( "--remove-padding takes <sectionname> <elementsize>" );

			char * n = rempad_sections[rempad_idx]=argv[++i];
			int s = rempad_elsize[rempad_idx]=atoi(argv[++i]);
			printf(" * remove padding from array section %s element size %d\n", n, s );

			rempad_idx++;
		}
		else
		{
			printf( "unknown argument: %s\n", argv[i] );
			exit(1);
		}
	}

	int handle;
	handle = open( argv[1], O_RDWR );
	if ( handle <= 0 )
		error( "Cannot open file" );

	long long flen = lseek( handle, 0, SEEK_END );
	lseek( handle, 0, SEEK_SET );

	unsigned char * buf = (unsigned char*) malloc( flen );
	read( handle, buf, flen );


	struct filehdr * h = (struct filehdr*) buf;

	printf("Magic: %04x\n", h->h_magic);
	printf("Sections: %d\n", h->h_nsections );
	printf("Timedate: %d\n", h->h_timdat );
	printf("Symbol Pointer: %x\n", h->h_symptr );
	printf("Number of symbols: %x\n", h->h_nsyms );
	printf("Optional header len: %d\n", h->h_opthdr);
	printf("Flags: %x\n", h->h_flags);

	sectionhdr* sec = (sectionhdr*) (buf + sizeof(filehdr));

	printf("SECTION nr vaddr    size     name         flags\n");
	for ( int i = 0; i < h->h_nsections; i++)
	{
		const char * sname;
		printf("section %2d %08x %08x %-12s %08x", i,
			sec[i].s_vaddr,
			sec[i].s_size,
			sname = getname( sec[i].s_name, h ),
			sec[i].s_flags
		);

		for ( int j = 0; j < rempad_idx; j++ )
		{
			if ( strcmp( sname, rempad_sections[j] ) == 0 )
			{
				int mod = sec[i].s_size % 10;
				printf( " padding=%d", mod );
				if ( mod != 0 )
				{
					int newsize = sec[i].s_size - mod;
					printf(": new size := 0x%x\n", newsize );
					lseek( handle, (unsigned char*)&(sec[i].s_size) - buf, SEEK_SET );
					write( handle, &newsize, 4 );
				}
			}
		}

		printf("\n");
	}

	close( handle );

	//struct aouthdr * h = (struct aouthdr*) buf;
}
