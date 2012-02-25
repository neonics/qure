SECTORS := $(shell perl -e 'use POSIX; print ceil((-s "build/boot.bin") * 1.0 / 512)')

ISO_ARGS = -boot-load-seg 0
#ISO_ARGS += -boot-load-size $(SECTORS)
#ISO_ARGS += -no-emul-boot
#ISO_ARGS += -hard-disk-boot

.PHONY: all clean init

all: os.iso

os.iso: init build/boot.img
	@echo Generating $@
	@echo "Sectors: $(SECTORS)"
	@cp build/boot.img root/boot/boot.img
	genisoimage -o os.iso \
		-r -b boot/boot.img \
		$(ISO_ARGS) \
		root/ 
	#-J -boot-info-table 
	#-boot-load-size 2884 \
	#-no-emul-boot \
	#-hard-disk-boot 

init:
	[ -d build/ ] || mkdir -p build/
	[ -d root/boot/ ] || mkdir -p root/boot/

clean:
	rm -rf build/ os.iso root/boot/build.img

build/boot.img: build/boot.bin build/write.exe
	build/write.exe -b build/boot.bin -o $@ && chmod 644 $@


#ASSEMBLER=FASM
ASSEMBLER=GAS


build/boot.bin: bootloader.s print.s sector1.s pmode.s gfxmode.s menu.s \
	floppy.s print2.s acpi.s pic.s gdt.s idt.s tss.s
#other-assemblers/bootloader-fasm.asm
ifeq ($(ASSEMBLER),FASM)
	d:/apps/fasm/FASM.EXE other-assemblers/bootloader-fasm.asm $@
	cp other-assemblers/bootloader-fasm.bin $@
else
ifeq ($(ASSEMBLER),GAS)
	/bin/as -R -n --warn --fatal-warnings -o build/bootloader.o bootloader.s
	util/checksymbols build/bootloader.o
	objcopy -O binary build/bootloader.o $@
endif
endif


# Utility - Build Assistance

util:	init build/write.exe build/asm.exe build/malloc.exe

build/write.exe: util/write.cpp
	gcc $< -o $@


build/asm.exe: util/asm.y util/asm.l
	@#flex -o build/asm.lex.c $<
	@#gcc build/asm.lex.c -o $@
	@# -d: gen header file -v report state -t debug
	bison -d -v -t -o build/asm.parser.c util/asm.l
	flex -DBISON -o build/asm.lex.c util/asm.y
	gcc -o $@ build/asm.lex.c build/asm.parser.c

build/malloc.exe: util/malloc.cpp
	gcc -std=c++0x -o $@ $<
