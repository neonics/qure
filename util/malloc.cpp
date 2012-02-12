#include <stdio.h>
#include <unistd.h>
#include <string.h>

#define malloc(...) my_malloc( __VA_ARGS__ )
#define free(...) my_free( __VA_ARGS__ )

#define MALLOC_SIZE 10240
#define ALLOC_HANDLES 1024

void * mem;
void * root = 0;

long heap_free = 0;
long used = 0;

struct handle
{
	void * addr;
	long size;
	bool isfree;
	int next;
	int prev;
} * handles;
long numhandles = 0;
long maxhandles;
long frag_free = 0; // sum( handle[*].size )

#define max(a, b) (a<b?b:a)
#define log(a, ...) printf(a "\n", __VA_ARGS__ )

void * internal_malloc( long size )
{
	if ( heap_free < size )
	{
		long allocsize = max( size, MALLOC_SIZE );
		void * newmem = sbrk( allocsize );
		memset( newmem, 0, allocsize );

		heap_free += allocsize;

		if ( ! root )
		{
			root = newmem;
		}

		mem = newmem;
	}

	void * ret = (void*) ((long)mem + used );
	heap_free -= size;
	used += size;
	return ret;
}

int first_free = -1;
int last_free = -1;



void unlink( int i )
{
	handles[i].isfree = true;

	if ( i == first_free )
		first_free = handles[i].next;

	// unlink prev-ref from next
	if ( handles[i].next >= 0 )
		handles[ handles[i].next ].prev = handles[i].prev;
	if ( handles[i].prev >= 0 )
		handles[ handles[i].prev ].next = handles[i].next;

	// unlink next-ref from cur
	handles[i].next = handles[i].prev = -1;

	// if ( i == first_free ) first_free = -1;
}

#define debug(m) printf(m "\n")
#define debugv(m, ...) printf(m "\n", __VA_ARGS__)


void insert( int i, int at )
{
	struct handle * n = & handles[i];
	struct handle * c = & handles[at];

	n->next = at;

	if ( c->prev >= 0 )
		n->prev = c->prev;

	c->prev = i;
}

void insertfree( int h )
{
	struct handle * n = & handles[ h ];
	n->prev = -1;
	n->next = -1;

	if ( first_free < 0 )
	{
		first_free = last_free = h;
	}
	else
	{
		// assume ordered by addr
		void * addr = n->addr;

		for ( int i = first_free; i >= 0; i = handles[i].next )
		{
			debugv( "check new %d:%x against %d:%x",
				h, addr, i, handles[i].addr );
			if ( addr < handles[i].addr )
			{
				debugv( "prepend %d to %i", h, i );
				insert( h, i );
				return;
			}

			if ( handles[i].next < 0 )
			{
				debugv( "appending %d to %d", h, i );
				handles[i].next = h;
				handles[h].prev = i;
				return;
			}
		}
	}
}



void * malloc( long size )
{
	for ( int i = 0; i < numhandles; i ++)
		if ( handles[i].isfree && size <= handles[i].size )
		{
			unlink( i );
			handles[i].isfree = false;
			frag_free -= handles[i].size;

			// insert part that is free as new handle
			// if the size is not too small
			if ( handles[i].size / size >= 2 && size >= 16 )
			{
				// todo: align
				handles[numhandles++] = { 
					(void*)((int)(handles[i].addr) + size),
					handles[i].size - size,
					true, -1, -1
				};

				insertfree( numhandles -1 );



				printf( "split handle %d size %ld into "
					"%d size %ld and %d size %ld\n",
					i, handles[i].size,
					i, size,
					numhandles-1,
					handles[numhandles-1].size );

				handles[i].size = size;
			}
			else
			{
				printf( "reuse %d %x %d of %d bytes\n",
					i, handles[i].addr, size,
					handles[i].size );
			}
			return handles[i].addr;
		}

	void * ret = internal_malloc( size );

	if ( !numhandles )
	{
		handles = (struct handle*) internal_malloc(
			ALLOC_HANDLES * sizeof( struct handle ) );
		maxhandles = ALLOC_HANDLES;
	}
	printf( "alloc %d %x %d bytes\n", numhandles, ret, size );

	handles[ numhandles ++ ] = { ret, size, false, -1, -1 };

	return ret;
}

bool inline contiguous( int i, int j )
{
	return i < 0 || j < 0 ? false :
		(int) handles[i].addr + handles[i].size == (int) handles[j].addr;
}

//void inline swap( int a, int b ) { int tmp = a; a = b; b = tmp; }

void free( void * addr )
{
	for ( long i = 0; i < maxhandles; i ++ )
		if ( handles[i].addr == addr )
		{
			unlink( i );

			frag_free += handles[i].size;

			debugv( "free %d %x %ld bytes", 
				i, handles[i].addr, handles[i].size );

			insertfree( i );
			return;
		}
	printf("error: %x not malloc()ed\n", addr );
}


char dump_hdr[] = "| TYPE  | BASE     | SIZE     | USED     | FREE     |\n";
char dump_frag_hdr[] = "| TYPE  | BASE     | SIZE     | PREV   | INDEX  | NEXT   |\n";
char dump_sep_line[] = "-------------------------------------------------------------\n";

char dump_line[] = "| %-5s | %x | %8ld | %8ld | %8ld |\n";
char dump_frag_line[] = "| %-5s | %x | %8ld | %6ld | %6ld | %6ld |\n";

void dumpmem()
{
	if ( ! mem ) printf("> No managed memory\n");
	else
	{
		printf( "\n" );
		printf( dump_hdr );
		printf( dump_line, 
			"heap",
			(long)root, 
			(long)sbrk( 0 ) - (long)root,
			used,
			heap_free
			);

		printf( dump_line, 
			"frag",
			-1,
			frag_free, 0, frag_free );
		printf( dump_sep_line );

		printf( dump_frag_hdr );

		//printf( "> memory segments/handles:\n" );
		for ( int i = 0; i < numhandles; i ++ )
			printf( dump_frag_line,
				handles[i].isfree ? "free":"alloc",
				handles[i].addr,
				handles[i].size, 
				handles[i].prev,
				i, 
				handles[i].next
			);


		printf( dump_sep_line );
		if ( first_free >= 0 )
		{
			long tf = 0;
			printf( "> free space chain: first = %d last = %d\n",
				first_free, last_free );

			int last = -10;
			for ( int i = first_free; /*handles[i].isfree &&*/ i >= 0; i = handles[i].next )
			{
				if ( i == last )
				{
					debug( "!!! infinite loop" );
					break;
				}
				last = i;
				printf( dump_frag_line,
					"ffrag",
					handles[i].addr,
					handles[i].size, 
					handles[i].prev,
					i, 
					handles[i].next
				);

				tf += handles[i].size;
			}

		}

		printf( "\n" );
	}
}

int main(int argc, char ** argv)
{
	printf("Hello world!\n");
	dumpmem();
	void ** l = (void**) malloc( 1024 );
	int i = 0;
	l[i++] = malloc( 0x100 );
	l[i++] = malloc( 0x100 );
	l[i++] = malloc( 0x100 );
	l[i++] = malloc( 0x100 ); dumpmem();
	free( l[2] ); dumpmem();
	l[i++] = malloc( 0x80 ); dumpmem();
	l[i++] = malloc( 0x100 ); dumpmem();
	free(l[0] ); dumpmem();
	free(l[3] ); dumpmem();
	free(l[2] ); dumpmem(); // should merge
}
