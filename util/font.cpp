// AngelCode 'Bitmap Font Generator' file format convertor
//

#include <sys/types.h> /* unistd.h needs this */
#include <unistd.h>    /* contains read/write */
#include <fcntl.h>
#include <string.h> // memset
#include <stdio.h> // printf, fopen
#include <stdlib.h> // atoi

int verbose = 0;

int main(int argc, char** argv)
{
	if ( argc!= 2)
	{printf("usage: thisprogram fontfile.fnt\n\nfontfile.fnt is an 'angelcode bitmap font generator' file.\n");return 255;}

	char path[1024]; path[0]=0;
	char * pathend = strrchr( argv[1], '/' );
	if ( pathend ) strncat( path, argv[1], pathend - argv[1] + 1);
	//for ( int i = 0; argv[1] + i <= pathend; i ++)
	//	path[i] = argv[1][i];
	// path[strlen(path)-1]=0;



	// text file describing the stuff
	int f = open( argv[1], O_RDONLY );
	long long flen = lseek( f, 0, SEEK_END );
	lseek( f, 0, SEEK_SET );

	char * in = (char*)malloc( flen + 1 ); in[flen]=0;
	read( f, in, flen );

	char fontname[100];
	int fontsize; // pixels
	int bold, italic;
	char charset[21];
	int unicode, stretchH, smooth, aa, padding1,padding2,padding3,padding4,
		spacing1, spacing2, outline;
	int linenr=1;

	if ( 16!=sscanf( in, "info face=%s size=%d bold=%d italic=%d charset=%s unicode=%d stretchH=%d smooth=%d aa=%d padding=%d,%d,%d,%d spacing=%d,%d outline=%d\n",
		fontname,
		&fontsize,
		&bold,
		&italic,
		charset,
		&unicode,
		&stretchH,
		&smooth,
		&aa,
		&padding1,&padding2,&padding3,&padding4,
		&spacing1, &spacing2,
		&outline
		) )
	{ printf("Can't parse file: error at line %d\n", linenr ); return 1;}
	while (*in++ != '\n'); linenr++;
	memmove( fontname, fontname+1, strlen(fontname)-1);
	fontname[strlen(fontname)-2]=0;
	if ( verbose )
		printf( "Font: '%s' %dpx ", fontname, fontsize );

	int lineHeight, base, scaleW, scaleH, pages, packed, alpha, red, green, blue;

	if ( 10 != sscanf( in, "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=%d packed=%d alphaChnl=%d redChnl=%d greenChnl=%d blueChnl=%d\n",
		&lineHeight, &base, &scaleW, &scaleH, &pages, &packed, &alpha, &red, &green, & blue
	) )
	{ printf("Can't parse file: error at line 2\n"); return 2; }
	while (*in++ != '\n'); linenr++;
	if ( verbose )
		printf("image %dx%d \n", scaleW, scaleH );


	char outfilenamebase[128];
	char outfilename_s[128]; outfilename_s[0]=0;
	char outfilename_bin[128]; outfilename_bin[0]=0;
	fontname[strlen(fontname)-1]=0;
	//sprintf( outfilename, "%s.s", fontname+1 );
	for ( int i = 0; i < strlen( argv[1]) && argv[1][i]!='.'; i ++)
	{	outfilenamebase[i] = argv[1][i]; outfilenamebase[i+1]=0;}
	strcat(outfilename_s, outfilenamebase); strcat(outfilename_s, ".s");
	strcat(outfilename_bin, outfilenamebase); strcat(outfilename_bin, ".bin" );

	FILE * out = fopen( outfilename_s, "w+" );
	if ( out ==0 ) { perror("create file");printf("Error opening '%s'\n", outfilename_s ); return 3;}

	fprintf( out, "###########################################\n## Font: %s\n", fontname+1 );
//	fprintf( out, ".long %d, %d # width, height per char\n", w, h );

	FILE * outbin = fopen( outfilename_bin, "w+" );
	if ( outbin ==0 ) { perror("create file");printf("Error opening '%s'\n", outfilename_bin ); return 3;}


	for ( int p = 0; p < pages; p ++ )
	{
		int page; char file[128];
		int a = 0;
		if ( 2!=(a = sscanf( in, "page id=%d file=%s\n", &page, file )) )
		{ printf("Can't parse file: error at line %d\n", linenr ); return 1;}
		while (*in++ != '\n'); linenr++;

		char imgfile[1024]; imgfile[0]=0;
		strcat( imgfile, path );
		file[strlen(file)-1]=0;
		strcat( imgfile, file+1 );

		if ( verbose )
			printf("  page %d file %s", page, imgfile );

		// use imagemagick to convert the file to a raw file
		char tgtfile[100];//strlen(file)+4];
		sprintf(tgtfile, "%s.raw", imgfile);
		char cmd[1024];
		sprintf(cmd, "convert %s gray:%s", imgfile, tgtfile );
		system(cmd);

		int fimage = open( tgtfile, O_RDONLY );
		if ( fimage <= 0 ) { perror(imgfile);printf("Can't open file '%s'\n", tgtfile);return 2;}
		int imsize = lseek(fimage, 0, SEEK_END);
		lseek(fimage,0,SEEK_SET);
		unsigned char * image = (unsigned char*)malloc(imsize);
		read(fimage, image, imsize);
		unlink(tgtfile);


		int numchars;
		if ( 1 != sscanf( in, "chars count=%d\n", &numchars ) )
		{ printf("Can't parse file: error at line %d\n", linenr ); return 1;}
		while (*in++ != '\n'); linenr++;

		if ( verbose )
		printf( " %d chars", numchars );

		int charsSoFar=0;

		for ( int i = 0; i < numchars; i ++)
		{
			int	charnr, x, y, w, h, xoffs, yoffs, page, chnl;
			if ( 10 != sscanf( in, "char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=%d chnl=%d\n",
				&charnr, &x, &y, &w, &h, &xoffs, &yoffs, &page, &chnl ) )
			{ printf("Can't parse file: error at line %d\n", linenr ); return 1;}
			while (*in++ != '\n'); linenr++;

			// print ascii font (like banner)
			if (0)
			{
				printf("\n");
				for ( int v = y; v < y + h; v ++ )
				{
					printf("%d:'",v-y);
					for ( int u = x; u < x + w; u ++ )
					{
						unsigned char c = image[ scaleW * v + u ];
						printf("%c", c < 128? ' ':'*');
					}
					printf("'\n");
				}
			}

			if ( w > 24 && w <= 32 )
			{
				if ( charsSoFar==0)
				{
					long n = 0;
					for ( ; charsSoFar < charnr; charsSoFar++)
					{
						fprintf(out, "# %d\n.long 0", charsSoFar );
						fwrite(&n, 1, 4, outbin);
						for ( int v = y+1; v < y + h; v ++ )
						{
							fprintf(out, ",0");
							fwrite(&n, 1, 4, outbin);
						}
						fprintf(out, "\n");


					}
				}

				fprintf(out, "# %d '%c'\n", charnr, charnr );
				for ( int v = y; v < y + h; v ++ )
				{
					fprintf(out, ".long 0b");
//					for ( int u = x + w-1; u >= x; u-- )
					for ( int u = x; u< x+w; u++ )
						fprintf(out, "%d", image[scaleW * v + u] < 128?0:1 );
					fprintf(out, "\n");

					long l = 0;
					for ( int u = x; u< x+w; u++ )
					{
						l<<=1;
						l|= image[scaleW*v+u]<128?0:1;
					}

					fwrite(&l, 1, 4, outbin);
				}
			}
			else
			{
				printf("char with not supported: %d (supported: 25..32)\n", w );
				return 5;
			}

		}
		if ( verbose )
			printf("\n");
	}
}
