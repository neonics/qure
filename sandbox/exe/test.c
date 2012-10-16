#include <stdio.h>

extern __cdecl void hello();

int main( int argc, char ** argv )
{
	hello();
	printf( "Hello %s!\n", "World" );
	printf( "Another string.\n");
}
