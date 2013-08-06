define CALC_SECTORS
$(shell perl -e 'use POSIX; print ceil((-s "$(1)") * 1.0 / 512)')
endef

GCC = gcc -x c -std=c99

ISO_ARGS = -boot-load-seg 0
ISO_ARGS += -boot-load-size $(SECTORS)
#ISO_ARGS += -J
#ISO_ARGS += -no-emul-boot
#ISO_ARGS += -hard-disk-boot


MSGPFX="    "
define MAKE
	@echo "$(MSGPFX)M $(1) $(2)"
	@make --no-print-directory -C $(1) $(2)
endef


.PHONY: all clean init build-deps

all: os.iso

os.iso: SECTORS = $(call CALC_SECTORS,build/boot.img)
os.iso: init build/boot.img
	@echo Generating $@
	@echo "Sectors: $(SECTORS)"
	@cp --sparse=always build/boot.img root/boot/boot.img
	@genisoimage -input-charset utf-8 -o os.iso.tmp \
		-r -b boot/boot.img \
		$(ISO_ARGS) \
		root/ && cp --sparse=always os.iso.tmp os.iso && rm os.iso.tmp
	@#-J -boot-info-table
	@#-no-emul-boot
	@#-hard-disk-boot

init:	build-deps
	[ -d build/ ] || mkdir -p build/
	[ -d root/boot/ ] || mkdir -p root/boot/

build-deps:
	@as -o /dev/null /dev/null || (echo "missing binutils" && false)
	@gcc --version > /dev/null || (echo "missing gcc" && false)
	@perl -v > /dev/null || (echo "missing perl" && false)
	@convert > /dev/null || (echo "missing imagemagic" && false)
	@genisoimage --version > /dev/null || (echo "missing genisoimage" && false)

clean:
	[ -d build ] && rm -rf build || true
	[ -f os.iso ] && rm os.iso || true
	[ -d root/boot/ ] && rm -rf root/boot/ || true
	$(call MAKE,bootloader,clean)
	$(call MAKE,kernel,clean)
	$(call MAKE,fonts,clean)

build/boot.img: build/boot.bin kernel build/write.exe
	@build/write.exe -o $@ \
		-b bootloader/boot.bin \
		-rd \
		-b build/kernel.bin \
		-b build/kernel.reloc \
		-b build/kernel.sym \
		-b build/kernel.stabs \
	&& chmod 644 $@

build/boot.bin:
	$(call MAKE,bootloader)

.PHONY: kernel
kernel: build/kernel.bin build/kernel.reloc build/kernel.sym build/kernel.stabs

build/kernel.bin: fonts
	$(call MAKE,kernel) && mv kernel/kernel.bin $@

build/kernel.reloc: build/kernel.bin
	util/reloc.pl kernel/kernel.o build/kernel.reloc

build/kernel.sym: build/kernel.bin
	util/symtab.pl kernel/kernel.o build/kernel.sym

build/kernel.stabs: build/kernel.bin
	util/stabs.pl kernel/kernel.o build/kernel.stabs

.PHONY: fonts
fonts:
	$(call MAKE,fonts)


# Utility - Build Assistance

util:	init build/write.exe build/asm.exe build/malloc.exe

build/write.exe: util/write.cpp
	@echo " C $@"
	$(GCC) $< -o $@

build/malloc.exe: util/malloc.cpp
	@echo " C $@"
	@g++ -std=c++0x -o $@ $<

build/font.exe: util/font.cpp
	@echo " C $@"
	echo $gcc -x c -std=c99 $< -o $@

##########################################################################

site:	root/www/site.html all
	[ -d root/www/screenshots ] || mkdir -p root/www/screenshots
	[ -d root/www/download ] || mkdir -p root/www/download
	cp -a DOC/Screenshots/*.png root/www/screenshots/
	[ -f root/www/download/boot.img.gz ] && rm root/www/download/boot.img.gz || true
	[ -f root/www/download/os.iso.gz ] && rm root/www/download/os.iso.gz || true
	gzip build/boot.img -c > root/www/download/boot.img.gz
	gzip os.iso -c > root/www/download/os.iso.gz
	[ -d root/src/kernel ] || mkdir -p root/src/kernel
	cp -a TODO Makefile 16 bootloader kernel util fonts root/src/kernel
	[ -d root/src/kernel/DOC ] || mkdir -p root/src/kernel/DOC
	cp DOC/* root/src/kernel/DOC/

site-clean:
	rm -rf root/www/screenshots root/www/download root/src/
