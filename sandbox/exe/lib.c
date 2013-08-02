
extern int __main() {}

extern int printf( const char * fmt, ...) {}

__cdecl void hello() {}

extern int perror(const char*a);
extern void exit(int a);
extern int lseek(int f,int o,int w);
extern int read(int f,void*b,int s);
extern int open(const char*n,int f);
extern void* malloc(int s);
extern const char* asnprintf(char*b,int*s,const char*fmt,...);

extern int puts(const char *s) {}
