%{

#include <stdio.h>
#include <stdlib.h>
#define YYERROR_VERBOSE
#include "asm.parser.h"

#include "../util/asm.h"

void yyerror( YYLTYPE * locp, const char * fname, char const * s )
{
	extern char * curtoken;
	fprintf( stderr, "%s[%d:%d-%d:%d]: token '%s': %s\n",
		fname,
		locp->first_line, locp->first_column,
		locp->last_line, locp->last_column,
		curtoken, s );
}
%}

%locations
%define api.pure
// need to have this in order to have YYLTYPE * yyloc as first arg
// the second arg this creates is a dummy....
%parse-param { const char * input_file }

//%union {
//	char * text;
//	long value;
//}

%token <text> COMMENT
%token <text> ID
%token <text> OPCODE
%token <text> REGISTER
%token <text> CONSTANT
%token <text> SIZE
%token END 0

%%

input: {printf("EMPTY\n");}
	| input instruction { printf("[input instruction]\n" ); }
	| input COMMENT { printf("comment: %s\n", $<text>2 ); }
	| END
;

instruction:
	OPCODE {printf("instruction %s\n", $<text>$ );}
	| OPCODE arg { printf("Opcode %s %s\n", $<text>$, $<text>2 ); }
	| OPCODE arg ',' arg { printf("Opcode %-8s %s, %s\n", $<text>$, $<text>2, $<text>4 ); }
;

	/*
	args:	arg
		| args ',' arg
	;
	*/

arg:	REGISTER | memexpr | constant;

memexpr:
	  memexpr_pfx "[" selreg ":" regexpr "]"
	| memexpr_pfx selreg ":" "[" regexpr "]"
	;

memexpr_pfx:
	| "offset"
	| SIZE "ptr"
	;

selreg: "cs" | "ds" | "es" | "fs" | "gs" | "ss";

regexpr: REGISTER
	| constant
	| regexpr "+" regexpr
	| REGISTER "*" mulnum
	;

constant: CONSTANT { printf("CONSTANT: hex %x, dec %d (%s)\n", $<value>$, $<value>$, $<text>$ ); }

mulnum:	"2" | "4" | "8";



%%


int main( int argc, char ** argv )
{
	extern FILE* yyin;
	const char * infile = "stdin";
	yyin = argc > 1 ? fopen( infile = argv[1], "r" ) : stdin;
	//YYLTYPE location;
	return yyparse( infile );
}
