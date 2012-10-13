#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h> // exit
#include <string.h>


struct filehdr {
unsigned short  f_magic;        /* magic number */
unsigned short  f_nscns;        /* number of sections */
long            f_timdat;       /* time & date stamp */
long            f_symptr;       /* file pointer to symbolic header */
long            f_nsyms;        /* sizeof(symbolic hdr) */
unsigned short  f_opthdr;       /* sizeof(optional hdr) */
unsigned short  f_flags;        /* flags */
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


struct scnhdr {
char            s_name[8];      /* section name */
long            s_paddr;        /* physical address, aliased s_nlib */
long            s_vaddr;        /* virtual address */
long            s_size;         /* section size */
long            s_scnptr;       /* file ptr to raw data for section */
long            s_relptr;       /* file ptr to relocation */
long            s_lnnoptr;      /* file ptr to gp histogram */
unsigned short  s_nreloc;       /* number of relocation entries */
unsigned short  s_nlnno;        /* number of gp histogram entries */
long            s_flags;        /* flags */
};


void error( char * msg )
{
	perror( msg );
	exit(1);
}



int main(int argc, char ** argv)
{
	if ( argc != 2)
	{
		printf("usage: %s <filename.o>\n", argv[0]);
		error("no filename");
	}

	int handle;
	handle = open( argv[1], O_RDONLY );
	if ( handle <= 0 )
		error( "Cannot open file" );

	long long flen = lseek( handle, 0, SEEK_END );
	lseek( handle, 0, SEEK_SET );

	unsigned char * buf = (unsigned char*) malloc( flen );
	read( handle, buf, flen );

	struct filehdr * h = (struct filehdr*) buf;

	printf("Magic: %04x\n", h->f_magic);
	printf("Sections: %d\n", h->f_nscns );
	printf("Timedate: %d\n", h->f_timdat );
	printf("Symbol Pointer: %x\n", h->f_symptr );
	printf("Number of symbols: %x\n", h->f_nsyms );
	printf("Optional header len: %d\n", h->f_opthdr);
	printf("Flags: %x\n", h->f_flags);

	//struct aouthdr * h = (struct aouthdr*) buf;
}
