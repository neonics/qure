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

#define E_SYMNMLEN 8
typedef union {
	char e_name[E_SYMNMLEN];
	struct {
	  unsigned long e_zeroes;
	  unsigned long e_offset;
	} e;
} SYMNAME;

#pragma pack(1)
typedef struct
{
	/*
  union {
	char e_name[E_SYMNMLEN];
	struct {
	  unsigned long e_zeroes;
	  unsigned long e_offset;
	} e;
  } e;
  	*/
	SYMNAME e;
  unsigned long e_value;
  /**
	 0: N_UNDEF
	-1: N_ABS
	-2: N_DEBUG

  */
  short e_scnum;
  /**
	which C type
	low 4 bits: (no/void/char/short/int/long/float/double/struct/union/enum/member/unsigned(char/short/int/long)
	etc..
   */
  unsigned short e_type;
  unsigned char e_sclass;
  unsigned char e_numaux;
} SYMENT;




void error( const char * msg )
{
	if (errno)
		perror( msg );
	else
		printf( "%s\n", msg );
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

char __symname_tmp[9] = "12345678";
const char * getsymname( SYMNAME & p, struct filehdr * h, unsigned char * buf )
{
	__symname_tmp[8]=0;
	for ( int i = 0; i < 8; i ++)
		__symname_tmp[i]=p.e_name[i];

	return p.e.e_zeroes
	? __symname_tmp // sp[i].e.e_name
	: (char*)h + h->h_symptr + h->h_nsyms * 18 + p.e.e_offset
	;
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
			"      --relocate-source <addr>\n"
			"        adjusts the addresses in .stab (source lines)\n\n"
			"      --link <symbol>\n"
			"        links all symbols relative to <symbol> (i.e. .text).\n"
	);
}

struct args {
	bool verbose = 0;
	char * objfilename = NULL;

	char * rempad_sections[10];
	int rempad_elsize[10];
	int rempad_idx=0;
	int adjust_source = 0;

	char * link;
};

struct args parse_args(int argc, char ** argv)
{
	if ( argc < 2)
	{
		print_usage( argv );
		error("no filename");
	}

	struct args args;
	memset( &args, 0, sizeof( args ) );

	for ( int i = 1; i < argc; i++ )
	{
		if ( args.objfilename == NULL )
		{
			if ( argv[i][0] == '-' )
			{
				if ( strcmp( argv[i], "-v" )==0 )
					args.verbose=1;
				else
				{
					printf( "unknown option: %s\n", argv[i] );
					print_usage( argv );
					exit(1);
				}
			}
			else
				args.objfilename = argv[i];
		}
		else
		{
			if ( strcmp( "--remove-padding", argv[i] ) == 0 )
			{
				if ( args.rempad_idx == 9 ) error( "array too small - edit source" );
				if ( i+2 >= argc ) error( "--remove-padding takes <sectionname> <elementsize>" );

				char * n = args.rempad_sections[args.rempad_idx]=argv[++i];
				int s = args.rempad_elsize[args.rempad_idx]=atoi(argv[++i]);
				if ( args.verbose )
					printf(" * remove padding from array section %s element size %d\n",
						n, s );

				args.rempad_idx++;
			}
			else if ( strcmp( "--adjust-source", argv[i] ) == 0 )
			{
				if ( i+1 >= argc ) error( "--adjust-source takes <addr>" );
				if ( sscanf( argv[++i], "%x", &args.adjust_source ) != 1 )
					error( "invalid hex" );
			}
			else if ( strcmp( "--link", argv[i] ) == 0 )
			{
				if ( i+1 >= argc ) error( "--link takes <symbol>" );
				args.link = argv[++i];
				printf(" * linking against symbol %s\n", args.link );
			}
			else
			{
				printf( "unknown argument: %s\n", argv[i] );
				print_usage( argv );
				exit(1);
			}
		}
	}

	return args;
}

void handle_stab( struct args args, int handle, unsigned char * buf, struct filehdr * h, sectionhdr* sec, int i );
void handle_text( struct args args, int handle, unsigned char * buf, struct filehdr * h, sectionhdr* sec, int i );

const char * find_section( const char * name, filehdr * h, sectionhdr * sec, unsigned char * buf )
{
	const char * secptr = NULL;
	for ( int k = 0; k < h->h_nsections; k++)
	{
		if ( strcmp( name, getname( sec[k].s_name, h) ) == 0 )
		{
			//printf( "FOUND section %s at section %d (%08x) (buf=%08x)\n", name, k, sec[k].s_sectionptr, buf );
			secptr = (const char*)buf + sec[k].s_sectionptr;
		}
	}
	if ( secptr == NULL )
		printf(" !WARN! no %s\n", name );
	else
		printf( " found section %s at %08x\n", name, secptr );
	return secptr;
}

int main(int argc, char ** argv)
{
	struct args args = parse_args( argc, argv );

	int handle;
	handle = open( args.objfilename, O_RDWR );
	if ( handle <= 0 )
		error( "Cannot open file" );

	long long flen = lseek( handle, 0, SEEK_END );
	lseek( handle, 0, SEEK_SET );

	unsigned char * buf = (unsigned char*) malloc( flen );
	read( handle, buf, flen );


	struct filehdr * h = (struct filehdr*) buf;

	if ( args.verbose )
	{
		printf("Magic: %04x\n", h->h_magic);
		printf("Sections: %d\n", h->h_nsections );
		printf("Timedate: %d\n", h->h_timdat );
		printf("Symbol Pointer: %x\n", h->h_symptr );
		printf("Number of symbols: %x\n", h->h_nsyms );
		printf("Optional header len: %d\n", h->h_opthdr);
		printf("Flags: %x\n", h->h_flags);
	}

	// PE magic also: 742e
	if ( h->h_magic != 0x014c && h->h_magic != 0x5a4d )
	{
		printf("Wrong magic: %x\n", h->h_magic);
		return 1;
	}

	if ( args.verbose )
	{
		SYMENT * sp = (SYMENT*) (buf + h->h_symptr );

		if ( false ) // this works
		for ( int i = 0; i < h->h_nsyms; i ++ )
		{
			SYMENT se = sp[i];
			char * p = (char*)&se;
			printf("SYM %3d: (%08x) [val=%08x scnum=%04x type=%04x sclass=%02x numaux=%d %s\n",
				i,
				i * sizeof(SYMENT),
				

				sp[i].e_value, sp[i].e_scnum, sp[i].e_type, sp[i].e_sclass, sp[i].e_numaux,

				// slightly diffrent getname: instead of 2nd byte = hex ptr, use the struct:
				getsymname( sp[i].e, h, buf )
			);
			i += sp[i].e_numaux; // skip aux data
		}

		const unsigned char * symptr = buf + h->h_symptr;

		/*
		// first entry: .file 
		int i=-1;
		while ( symptr[++i] != 0 && i < 1000)
			printf("%c", symptr[i] );
		printf(" %02x", symptr[++i] );
		printf(" %02x", symptr[++i] );
		printf(" %08x", *(int*)( &symptr[++i] ) );
		i+=4;
		printf(" %08x", *(int*)( &symptr[i] ) );
		i+=4;
		printf(" %02x", symptr[i++] );
		printf(" %02x", symptr[i] );

		printf("\n");


		for ( int q = 0; q < 3; q ++ )
		{
		while ( symptr[++i] != 0 && i < 1000)
			printf("%c", symptr[i] );
		printf(" %02x", symptr[++i] );
		printf(" %02x", symptr[++i] );
		printf(" %08x", *(int*)( &symptr[++i] ) );
		i+=4;
		printf(" %08x", *(int*)( &symptr[i] ) );
		i+=4;
		printf(" %02x", symptr[i++] );
		printf(" %02x", symptr[i++] );
//		printf(" %02x", symptr[i] );

		printf("\n");
		}
		for ( int i = 0; i < 1000; i ++ )
		{
			unsigned char c = symptr[i];
			printf("%4d: %02x (%c)\n", i, c, c>=' '&&c<128?c:' ');
		}
		printf("\n");
		*/
	}

	sectionhdr* sec = (sectionhdr*) (buf + sizeof(filehdr) + h->h_opthdr);

	if ( args.verbose )
		printf("SECTION nr vaddr    size     name         flags    reloc    numreloc\n");
	for ( int i = 0; i < h->h_nsections; i++)
	{
		const char * sname = getname( sec[i].s_name, h );
		if ( args.verbose )
			printf("section %2d %08x %08x %-12s %08x %08x %d\n", i,
				sec[i].s_vaddr,
				sec[i].s_size,
				sname,
				sec[i].s_flags,
				sec[i].s_relptr,
				sec[i].s_nreloc
			);
	}

	printf("\n");

	for ( int i = 0; i < h->h_nsections; i++)
	{
		const char * sname = getname( sec[i].s_name, h );
		if ( args.verbose )
			printf("section %2d %08x %08x %-12s %08x %08x %d", i,
				sec[i].s_vaddr,
				sec[i].s_size,
				sname,
				sec[i].s_flags,
				sec[i].s_relptr,
				sec[i].s_nreloc
			);


		for ( int j = 0; j < args.rempad_idx; j++ )
		{
			if ( strcmp( sname, args.rempad_sections[j] ) == 0 )
			{
				int mod = sec[i].s_size % 10;
				if ( args.verbose )
					printf( " padding=%d", mod );
				if ( mod != 0 )
				{
					int newsize = sec[i].s_size - mod;
					if ( args.verbose )
						printf(": new size := 0x%x\n", newsize );
					lseek( handle, (unsigned char*)&(sec[i].s_size) - buf, SEEK_SET );
					write( handle, &newsize, 4 );
					// also update section alignment
					lseek( handle, (unsigned char*)&(sec[i].s_flags) - buf, SEEK_SET );
					int newflags = sec[i].s_flags;
					newflags &=~0x00f00000;	// mask out section align flags
					newflags |= 0x00100000; // 1 byte alignment (NOPAD=8 is deprecated).
					write( handle, &newflags, 4);
					if ( args.verbose )
						printf("newflags:%08x",newflags);
				}
			}

		}

		if ( strcmp( ".text", sname ) == 0 )
			handle_text( args, handle, buf, h, sec, i );

		if ( strcmp( ".stab", sname ) == 0 )
			handle_stab( args, handle, buf, h, sec, i );

		if ( args.verbose )
			printf("\n");
	}

	close( handle );

	//struct aouthdr * h = (struct aouthdr*) buf;
}

void handle_text( struct args args, int handle, unsigned char * buf, struct filehdr * h, sectionhdr* sec, int i )
{
	#pragma pack(1)
	struct RELOC {
		unsigned long addr;
		unsigned long symidx;
	//	short a, b;
		/**
		 0x0006: dir32  ( 6 dec: RELOC_ADDR32)
		 0x0014: DISP32 (20 dec: RELOC_REL32)
		 0x0010: 16
		*/
		unsigned short flags;	// type

	};
	RELOC * rsp = (struct RELOC*)(buf + sec[i].s_relptr);
	unsigned char * stb = buf + sec[i].s_sectionptr;

	if ( args.verbose || args.link )
	{
		if ( args.verbose )
		printf("\nRELOCATION\n"); // close section info line

		SYMENT * se = (SYMENT*)(buf + h->h_symptr);

		SYMENT * linksym = NULL;

		// find the symbol - also when --link not specified, for verbose mode
		const char * lsymname = args.link ? args.link : ".text";
		for ( int i = 0; i < h->h_nsyms; i ++ )
			if ( strcmp( lsymname, getsymname( se[i].e, h, buf ) ) == 0 )
			{
				printf("-- linksym: [idx:%08x] %s %08x\n", i, lsymname, se[i].e_value );
				if ( linksym == NULL )
					linksym = &se[i];
			}
		if ( ! linksym )
			printf("error - symbol not found: %s", lsymname );
		
		//printf( " %x ", sec[i].s_sectionptr );

		for ( int k = 0; k < sec[i].s_nreloc; k ++ )
		{
			SYMENT * cs = & se[ rsp[k].symidx ];

			if ( args.verbose )
			printf ("%4d: %08x idx=%08x fl=%04x [%08x] %-12s", k,
				rsp[k].addr,
				rsp[k].symidx,
				rsp[k].flags,
				//((SYMENT*)(buf + h->h_symptr))[rsp[k].symidx]
				cs->e_value,
				getsymname( cs->e, h, buf )
			);

				long diff = cs->e_value;
				unsigned char * cp= ( buf + sec->s_sectionptr + (rsp[k].addr - sec->s_vaddr) );
				long oldv = *((long*)cp);



			if (args.link
				&& ( rsp[k].flags == 6	) // RELOC_ADDR32  (not RELOC_REL32 (20, 0x14)
				&& cs->e_value - linksym->e_value >= 0 // don't relocate before base of linksym
					// AND GNU BUG: don't relocate .text itself! it is already relocated.
			)
			{
				// relocate all, relative to 0; use linksym as sym, and update it to 0 later
				rsp[k].symidx = linksym - se; // - replace the relocation entry with a reference to linksym

				if ( args.verbose )
				printf(" -- FIX -- sym:%x->%x  diff=%08x old=%08x new=%08x",
					rsp[k].symidx, linksym-se,
					diff, oldv,
					oldv+diff
				);

				*((long*)cp) += diff;
			}
			else if ( rsp[k].flags == 20 ) // RELOC_REL32
			{
				if ( args.verbose )
					printf(" -- REL32 -- idx:%x  diff=%04x old=%04x new=%04x",
						rsp[k].symidx,
						diff & 0xffff, oldv & 0xffff, (oldv+diff)&0xffff
					);
				if ( args.link )
					*((long*)cp) += diff - rsp[k].addr - 4;
			}
			else if ( rsp[k].flags == 0x10 ) // 16 bit relocation
			{
				if ( args.verbose )
					printf(" -- reloc16 -- idx:%x  diff=%04x old=%04x new=%04x",
						rsp[k].symidx,
						diff & 0xffff, oldv & 0xffff, (oldv+diff)&0xffff
					);

// TODO: append symbol to the 'reset' list and clear at end of loop (so that reloc.pl won't relocate 16 bit addr)
// and enable the next line
				*((short*)cp) += 0xffff&diff;
				// also update the symbol value:
				// delay this to the end
//				cs->e_value = 0;
			}
			else
			{
				if ( args.verbose )
					printf(" -- symref -- idx:%08x  diff=%08x old=%08x new=%08x",
						rsp[k].symidx,
						diff, oldv, oldv+diff
					);

				//if ( args.link ) *((long*)cp) += diff;
			}

			if ( args.verbose )
			printf("\n");
		}

		if ( args.link != 0 )
		{
			// write the section payload
			lseek( handle, sec[i].s_sectionptr, SEEK_SET );
			write( handle, buf + sec[i].s_sectionptr, sec[i].s_size );
			// write the section relocation info (not needed, since not changed)
			lseek( handle, sec[i].s_relptr, SEEK_SET );
			write( handle, buf + sec[i].s_relptr, sec[i].s_nreloc * sizeof(RELOC) );

			// update the linksym address to 0
			linksym->e_value = 0;
			// write the symbol table
			lseek( handle, h->h_symptr, SEEK_SET );
			write( handle, buf + h->h_symptr, h->h_nsyms * sizeof(SYMENT) );
		}
	}
}

void handle_stab( struct args args, int handle, unsigned char * buf, struct filehdr * h, sectionhdr* sec, int i )
{
	// reverse engineer...

	#pragma pack(1)
	struct STAB {
		unsigned long sfile;	// index into .stabstr when linenr == 0
		unsigned short code;	// 0x44: SLINE; 0x84: SOL; 0x64: SO
		unsigned short linenr;
		unsigned long addr;
	};

	STAB * slp = (struct STAB*)(buf + sec[i].s_sectionptr);
	unsigned char * stb = buf + sec[i].s_sectionptr;


	if ( args.verbose )
	{
		// find .stabstr
		const char * stabstr = NULL;
		for ( int k = 0; k < h->h_nsections; k++)
		{
			if ( strcmp( ".stabstr", getname( sec[k].s_name, h) ) == 0 )
				stabstr = (const char*)buf + sec[k].s_sectionptr;
		}
		if ( stabstr == NULL )
			printf(" !WARN! no .stabstr" );

		printf( " %x ", sec[i].s_sectionptr );

		if ( false )
		for ( int k = 0; k < sec[i].s_size / 12; k ++ )
		{
			printf("%4d: ", k);
			printf("%08x %04x %5d %08x",
				slp[k].sfile, slp[k].code, slp[k].linenr, slp[k].addr);

			printf(" %s\n", slp[k].linenr==0
				? (stabstr == NULL ? "<..>" : stabstr + slp[k].sfile )
				:""
			);
		}
	}

	if ( args.adjust_source != 0 )
	{
		for ( int k = 0; k < sec[i].s_size / 12; k ++ )
			slp[k].addr += args.adjust_source;

		lseek( handle, sec[i].s_sectionptr, SEEK_SET );
		write( handle, slp, sec[i].s_size );
	}
}


