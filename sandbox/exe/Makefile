MSGPFX="    "
define MAKE =
	@echo "$(MSGPFX)M $(1) $(2)"
	@make --no-print-directory -C $(1) $(2)
endef


# -fPIC  position independent: GCC warns as this is the default.
# -fno-exceptions -fno-rtti -fno-stack-protector: unregocnized

# -fno-builtin \
#	-lno-stdlib -nostartfiles -nodefaultlibs \


# All CC options:
# -ansi  -std=standard  -aux-info filename -fno-asm  -fno-builtin
# -fno-builtin-function -fhosted  -ffreestanding  -fms-extensions
# -trigraphs  -no-integrated-cpp  -traditional  -traditional-cpp
# -fallow-single-precision  -fcond-mismatch -fsigned-bitfields
# -fsigned-char -funsigned-bitfields  -funsigned-char -fwritable-strings

#	-fno-builtin \


CC_OPTS = -save-temps \
	-mno-stack-arg-probe

# All Linker options:
#	-llibrary -nostartfiles  -nodefaultlibs  -nostdlib
#	-pie -s  -static  -static-libgcc  -shared  -shared-libgcc  -symbolic
#	-Wl,option  -Xlinker option -u symbol

#	--exclude-libs user32

# These options are not really necessary when calling LD directly instead of through gcc.
LD_OPTS = -nostartfiles -nodefaultlibs -nostdlib \
	--as-needed \
	--exclude-libs ALL \



# LD -T linker.d

#LOP = -Wl,
#
#GCC_OPTS = $(CC_OPTS) $(foreach o,$(LD_OPTS),-Wl,"$o")
#
#$(addprefix $(value LOP),$(LD_OPTS))
#
#subst -,$(LOP),-,$(LD_OPTS))
#
#-Wl,$(LD_OPTS: =,)



.PHONY: all clean init

all: Makefile libc.so a.exe a.elf
	cp a.elf ../../root/

init:


clean:
	rm -f test.[sio] default.[sio] default.c ?.exe ?.elf \
	*.dll *.so lib.[sio] libc.def libc.exp libc.o

%.o: Makefile

%.exe: Makefile

libc.dll: libc.o Makefile
	ld -shared -T libc.ld $(LD_OPTS) $< -o $@
	#dlltool -v -z libc.def -e libc.exp $@

libc.so: libc.dll
	objcopy -O elf32-i386 $< $@

libc.o: lib.c Makefile
	gcc -c $(CC_OPTS) $< -o $@

#%.exe: %.o
#	ld $< -o $@

test.o: test.c Makefile
	gcc -O3 -c $(CC_OPTS) $< -o $@

a.exe: test.o Makefile
	ld $(LD_OPTS) -pie -Bdynamic -L . -lc $< -o $@

a.elf: a.exe
	objcopy -O elf32-i386 $< $@
############ create reference files

default.c: test.c Makefile
	cp $< $@

b.exe: default.c Makefile
	gcc -WL,. -WL,c -save-temps $< -o $@
