define SECTORS =
	$(shell perl -e 'use POSIX; print ceil((-s "$(1)") * 1.0 / 512)')
endef

ISO_ARGS = -boot-load-seg 0
#ISO_ARGS += -boot-load-size $(SECTORS)
#ISO_ARGS += -no-emul-boot
#ISO_ARGS += -hard-disk-boot


MSGPFX="    "
define MAKE =
	@echo "$(MSGPFX)M $(1) $(2)"
	@make --no-print-directory -C $(1) $(2)
endef


.PHONY: all clean init

all: os.iso

os.iso: init build/boot.img
	@echo Generating $@
	@echo "Sectors: $(call SECTORS,build/boot.img)"
	@cp build/boot.img root/boot/boot.img
	@genisoimage -input-charset utf-8 -o os.iso \
		-r -b boot/boot.img \
		$(ISO_ARGS) \
		root/ 
	@#-J -boot-info-table 
	@#-boot-load-size 2884 
	@#-no-emul-boot 
	@#-hard-disk-boot 

init:
	[ -d build/ ] || mkdir -p build/
	[ -d root/boot/ ] || mkdir -p root/boot/

clean:
	[ -d build ] && rm -rf build || true
	[ -f os.iso ] && rm os.iso || true
	[ -f root/boot/build.img ] && rm root/boot/build.img || true
	$(call MAKE,bootloader,clean)
	$(call MAKE,kernel,clean)


build/boot.img: build/boot.bin build/kernel.bin build/write.exe
	@build/write.exe -o $@ \
		-b bootloader/boot.bin \
		-rd \
		-b kernel/kernel.bin \
	&& chmod 644 $@

build/boot.bin:
	$(call MAKE,bootloader)

build/kernel.bin:
	$(call MAKE,kernel)

build/kernel.o: sector1.s pmode.s gfxmode.s menu.s \
	floppy.s print2.s acpi.s pic.s gdt.s idt.s tss.s keyboard.s
	/bin/as -R -n --warn --fatal-warnings -o build/bootloader.o bootloader.s


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
