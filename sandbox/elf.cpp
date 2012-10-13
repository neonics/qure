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

struct elf_header {
	unsigned char	ident[4];	// 7F 'E' 'L' 'F'
	unsigned char	fileclass;
	unsigned char	dataencoding;
	unsigned char	fileversion;
	unsigned char	pad[16-7];
	//
	unsigned short	type;
	unsigned short	machine;
	unsigned long	version;
	unsigned long	entry;
	unsigned long	phoff;
	unsigned long	shoff;
	unsigned long	flags;
	unsigned short	ehsize;
	unsigned short	phentsize;
	unsigned short	phnum;
	unsigned short	shentsize;
	unsigned short	shnum;
	unsigned short	shstrndx;
};

const char * type_strings[] = { "NONE", "REL", "EXEC", "DYN", "CORE" };
const char * machine_strings[] = { "NONE", "M32", "SPARC", "386", "68K",
	"88K", "860", "MIPS", "MIPS_RS4" };
	
struct elf_shdr
{
	unsigned long name;
	unsigned long type;
	unsigned long flags;
	unsigned long addr;
	unsigned long offset;
	unsigned long size;
	unsigned long link;
	unsigned long info;
	unsigned long addralign;
	unsigned long entsize;
};

struct elf_symtab
{
	unsigned long	name;
	unsigned long	value;
	unsigned long	size;
	unsigned char	info;
	unsigned char	other;
	unsigned short	shndx;
};

void print_sectiondata( void * sectiondata, int size, int isascii )
{
	if ( !isascii )
	{
	for ( int j = 0; j < size; j++ )
	{
		unsigned char v = ((unsigned char*)sectiondata)[j];
		printf( "%02x ", v );
	}
	printf( "\n" );
	}

	for ( int j = 0; j < size; j++ )
	{
		unsigned char v = ((unsigned char*)sectiondata)[j];
		printf( "%c", v == 0 ? ' ' : v );
	}
	printf( "\n" );
}


int main(int argc, char ** argv)
{
	if ( argc != 2)
	{
		printf("usage: %s <filename.o>\n", argv[0]);
		error("no filename");
	}

	handle = open( argv[1], O_RDONLY );
	if ( handle <= 0 )
		error( "Cannot open file" );

	read( handle, buf, 2048 );
	sector++;

	struct elf_header * h = (struct elf_header*) buf;

	printf("ELF Header: ");
	for ( int i = 0; i < 16; i ++ )
		printf( "%02x ", h->ident[i] );
	printf("\n");

	if ( h->ident[0] != 0x7f || h->ident[1] != 'E' || h->ident[2] != 'L'
		|| h->ident[3] != 'F')
		error("Not an ELF file");

	printf( "  File Class: %d (%d bits)\n"
			"  Data Encoding: %d (%s)\n"
			"  File Version: %d\n",
		h->fileclass, 16 << h->fileclass,
		h->dataencoding, h->dataencoding == 1 ? "LSB" : h->dataencoding==2?"MSB":"invalid",
		h->fileversion );

	printf( "Type: %d (%s)\n", h->type, h->type <=4 ? type_strings[h->type] : "Unknown" );
	printf( "Machine: %d (%s)\n", h->machine, h->machine <=10
		? machine_strings[h->machine] : "Unknown" );
	printf( "Version: %d (%s)\n", h->version, h->version==0?"NONE":h->version==1?"Current":"?");
	printf( "Entry: 0x%x\n", h->entry );
	printf( "Program Header table offset: 0x%x\n", h->phoff );
	printf( "Section Header table offset: 0x%x\n", h->shoff );
	printf( "Flags: 0x%x\n", h->flags );
	printf( "ELF Header Size: 0x%x (hardcoded: 0x%x)\n", h->ehsize, sizeof(struct elf_header) );
	printf( "Program Header Table Entry Size: 0x%x (%d)\n", h->phentsize, h->phentsize );
	printf( "Program Header Table Entries: %d\n", h->phnum );
	printf( "Section Header Table Entry Size: 0x%x (%d) (hardcoded %d)\n", h->shentsize, h->shentsize, sizeof (struct elf_shdr) );
	printf( "Section Header Table Entries: %d\n", h->shnum );
	printf( "Section Header Name Table Index: %d\n", h->shstrndx );

	printf( "\nSections\n" );
	lseek( handle, h->shoff, SEEK_SET );
	int ss = h->shnum * h->shentsize;
	unsigned char * section = (unsigned char *) malloc( ss );
	struct elf_shdr * sections = (struct elf_shdr*) section;
	read( handle, section, ss );
	printf( " * Read sections: file offset 0x%x size %d\n", h->shoff, ss );

	void ** sectiondata = (void**)malloc( sizeof(void*) * h->shnum );

	for ( int i = 0; i < h->shnum; i++ )
	{
		struct elf_shdr * p = &sections[i];
		if ( p->size )
		{
			sectiondata[i] = malloc( p->size );
			lseek( handle, p->offset, SEEK_SET );
			read( handle, sectiondata[i], p->size );
		}
	}

	//struct elf_shdr * sh = (struct elf_shdr *) (section + h->shstrndx * h->shentsize );
	struct elf_shdr * sh = &sections[ h->shstrndx ];

#define STRING( s, strtab ) \
	strtab >= h->shnum ? "Invalid string table" : \
	s < sections[strtab].size \
		? ((const char*) sectiondata[strtab]) + s \
		: "<String index out of range>"

#define SECTIONNAME( n )  \
	n == 0 ? "UNDEF" : \
	n >= 0xff00 ? \
		n == 0xfff1 ? "ABS" : n == 0xfff2 ? "COMMON" \
			: asnprintf( NULL, NULL, "%x", n ) \
		: n < h->shnum ? STRING( sections[n].name, h->shstrndx ) \
		: "<Invalid section>" 

	for ( int i = 0; i < h->shnum; i++ )
	{
		struct elf_shdr * eh = & sections[i];

		if ( eh == sh ) printf("!!!!!");
		printf("Section %d (0x%x)\n", i, i );
		printf( "Name: 0x%x: %s\n", eh->name, 
			//&((const char*)sectiondata[ i ])[eh->name]
			//(const char*)sectiondata[ h->shstrndx ] + eh->name
			STRING( eh->name, h->shstrndx )
		);
		printf( "Type: 0x%x\n", eh->type );
		printf( "Flags: 0x%x %s %s %s %s\n", eh->flags,
			eh->flags & 1 ? "WRITE" : "",
			eh->flags & 2 ? "ALLOC" : "",
			eh->flags & 4 ? "EXEC" : "",
			eh->flags & 0xf000000 ? "[Special Proc]" : ""
		);
		printf( "Addr: 0x%x\n", eh->addr ); // 0 means not part of process mem image
		printf( "Offset: 0x%x\n", eh->offset ); // offset in file for section data
		printf( "Size: 0x%x\n", eh->size ); // size in file

		// Meaning of link and info depends on eh->type:
		// Type		Link		Info
		// DYNAMIC	strtab		0
		// HASH		symtab		0
		// REL/RELA	symtab		target section nr of relocation
		// SYMTAB	OS specific	OS specific
		// DYNSYM	OS specific	OS specific
		printf( "Link: 0x%x\n", eh->link ); // linked section header table index
		printf( "info: 0x%x\n", eh->info );
		printf( "Address alignment: 0x%x\n", eh->addralign );
		printf( "Entry Size: %d\n", eh->entsize );
		printf( "Section Type: " );
		if ( eh->type >= 0x70000000 )
		{
			if ( eh->type >= 0x80000000 )
				printf( "User reserved");
			else
				printf( "Processor-specific semantics" );

			//case 0x70000000: printf( "LOPROC\n" ); break;
			//case 0x7fffffff: printf( "HIPROC\n" ); break;
			//case 0x80000000: printf( "LOUSER\n" ); break;
			//case 0xffffffff: printf( "HIUSER\n" ); break;
		}
		else
		switch ( eh->type )
		{
			case 0: printf( "NULL\n" ); break;
			case 1: printf( "PROGBITS\n" ); break;
			case 2: printf( "SYMTAB\n" );
				struct elf_symtab * st = (struct elf_symtab*) sectiondata[i];
				if ( eh->entsize != sizeof( struct elf_symtab ) )
				{	
					printf("Entry size mismatch: expect %d, got %d\n",
						sizeof(elf_symtab), eh->entsize );
					break;
				}
				for ( int j = 0; j < eh->size / eh->entsize; j ++, st++ )
				{
					// value interpretation in relocatable files:
					//  for section COMMON (0xfff2), alignment constraint
					//  for other sections, offset into section st->shndx
					// in executable and shared (dll) files, st->value holds
					// a virtual (runtime memory) address, section number is
					// irrelevant here.

					// = For ABS sections (0xfff1), absolute value that does not
					// change under relocation.
					// = For COMMON sections (0xfff2), refers to an unallocated
					// block. Value is alignment constraints (like addralign).
					// Size indicates the memory to allocate/reserve.
					// = UNDEF section (0), undefined symbol, link with file
					// containing the symbol definition.
					printf( " 0x%08x", st->value );
					printf( " Name: %s", 
						((const char*)sectiondata[eh->link]) + st->name
					);
					printf( " Size: 0x%x (%d)", st->size, st->size );
					// info: bind, type
					unsigned char bind = st->info >> 4;
					unsigned char type = st->info & 0xf;
					printf( " Bind=%s Type=%s", //st->info,
						bind == 0 ? "LOCAL" :
						bind == 1 ? "GLOBAL" :
						bind == 2 ? "WEAK" :
						(bind >= 13 && bind <=15) ? "PROC" : "unknown",

						type == 0 ? "NOTYPE" :
						type == 1 ? "OBJECT" :
						type == 2 ? "FUNC" :
						type == 3 ? "SECTION" :
						type == 4 ? "FILE" :
						(type >= 13 && type <=15) ? "PROC" : "unknown"
					);

					printf( " Rel: (%s)\n", SECTIONNAME( st->shndx ) );
				}
				break;
			case 3: printf( "STRTAB\n" ); 
				print_sectiondata( sectiondata[i], eh->size, 1 );
				break;
			case 4: printf( "RELA\n" );
			{
				long * r = (long*) sectiondata[ i ];
				for ( int j = 0; j < eh->size / (2 * sizeof(long*)); j++ )
				{
					printf( "  ADDR %08x INFO %08x ADDEND %08x\n", *r++, *r++,
						*r++);
				}
				break;
			}
			case 5: printf( "HASH\n" ); break;
			case 6: printf( "DYNAMIC\n" ); break; 
			case 7: printf( "NOTE\n" ); break;
			case 8: printf( "NOBITS\n" ); break;
			case 9: printf( "REL\n" );
				long * r = (long*) sectiondata[ i ];
				for ( int j = 0; j < eh->size / (2 * sizeof(long*)); j++ )
				{
					printf( "  ADDR %08x INFO %08x: symtab: %d (%s) TYPE %d (%s)\n", r[j*2],
						r[j*2+1],

						(r[j*2+1])>> 8,

					"...",
					/*
						((struct elf_symtab*)
						&sectiondata[eh->link] // symbol table
						)[ 
						(r[j*2+1]>>8)
						],
*/
						
						(r[j*2+1]) & 0xff, "?" // (r[j*2+1]) & 0xff
						);
				}
				break;
			case 10: printf( "SHLIB\n" ); break;
			case 11: printf( "DYNSYM\n" ); break;
			default:
				printf( "Unknown\n" );
				print_sectiondata( sectiondata[i], eh->size, 0 );
				break;
		}

		printf( "\n" );

		// Special Sections
		// Name		Type		Flags
		// .bss		NOBITS		ALLOC WRITE
		// .comment	PROGBITS	none
		// .data	PROGBITS	ALLOC WRITE
		// .data1	PROGBITS	ALLOC WRITE
		// .debug	PROGBITS	none
		// .dynamic	DYNAMIC		
		// .hash	HASH		ALLOC
		// .line	PROGBITS	none
		// .note	NOTE		none
		// .rodata	PROGBITS	ALLOC		// read only data
		// .rodata1	PROGBITS	ALLOC
		// -----------------------------
		// .shstrtab STRTAB		none		// section names
		// .strtab	STRTAB		(ALLOC?)	// optional alloc
		// .symtab	SYMTAB		(ALLOC?)
		// .text	PROGBITS	ALLOC EXEC

	}

}
