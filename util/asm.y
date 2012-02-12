%{
#include <stdlib.h>
#include <math.h>
#define YYERROR_VERBOSE
int yycolumn = 1;
char * curtoken = "<none>";
#define YY_USER_ACTION yylloc->first_line = yylloc->last_line = yylineno; \
	yylloc->first_column = yycolumn; \
	yylloc->last_column = yycolumn + yyleng - 1; \
	yycolumn += yyleng; \
	yylval->text = curtoken = strdup(yytext);

#include "asm.parser.h"
%}
 
%option noyywrap yylineno
%option bison-bridge bison-locations

DIGIT    [0-9]
HD	 [0-9a-f]
ID       [a-z][a-z0-9]*


%%
'#'[^\n]+\n	yylval->text = strdup( yytext ); return COMMENT;

{HD}+h|0x{HD}+	yylval->text = strdup( yytext ); return CONSTANT;//printf( "HEX %x (%s)", strtol( yytext, 0, 16 ), yytext );


{DIGIT}+   	return CONSTANT;


{DIGIT}+"."{DIGIT}*        yylval->text = strdup( yytext ); return CONSTANT; //printf( "A float: %s (%g)\n", yytext, atof( yytext ) );

(?:mov|push[af]?|pop[af]?|inc|dec|add|sub|mul|div|loopn?z|int|l(ea|ds|es)|jmp|jn?[czelg]|j[abgl]e|jxx)	yylval->text = strdup( yytext ); return OPCODE;

(?i:[abcd]x|bp|sp|bp|si|di|[cdefg]s)	yylval->text = strdup( yytext ); return REGISTER;


{ID}        printf( "An identifier: %s\n", yytext ); yylval->text = strdup( yytext ); return ID;

"+"|"-"|"*"|"/"   printf( "An operator: %s\n", yytext ); return ID;

"{"[\^{}}\n]*"}"     /* eat up one-line comments */

","	return yytext[0];

\n          {printf("\n");} /* eat up whitespace */;

[ \t\n]+          /* eat up whitespace */

.           printf( "Unrecognized character: %s\n", yytext );

%%

#ifndef BISON
//#define YYPARSE_PARAM scanner
//#define YYLEX_PARAM scanner
main( int argc, char ** argv )
{
	yyin = argc > 1 ? fopen( argv[1], "r" ) : stdin;

	YYSTYPE type; YYLTYPE loc;
	yylex( &type, &loc );
}
#endif
