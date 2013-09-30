define CALC_SECTORS
$(shell perl -e 'use POSIX; print ceil((-s "$(1)") * 1.0 / 512)')
endef

GCC = gcc -x c -std=c99

ISO_ARGS = -boot-load-seg 0
ISO_ARGS += -boot-load-size $(SECTORS)
#ISO_ARGS += -J
#ISO_ARGS += -no-emul-boot
#ISO_ARGS += -hard-disk-boot

KERNEL_OBJ = kernel/kernel.obj


define MAKE
	@echo "  M     $(1) $(2)"
	@make -s --no-print-directory -C $(1) $(2)
endef


.PHONY: all clean init build-deps

all: os.iso

os.iso: SECTORS = $(call CALC_SECTORS,build/boot.img)
os.iso: init build/boot.img site
	@#echo "Sectors: $(SECTORS)"
	@cp --sparse=always build/boot.img root/boot/boot.img
	@echo "  ISO   $@"
	@genisoimage -P Neonics -quiet -input-charset utf-8 -o os.iso.tmp \
		-r -b boot/boot.img \
		$(ISO_ARGS) \
		root/ && cp --sparse=always os.iso.tmp os.iso && rm os.iso.tmp
	@#-J -boot-info-table
	@#-no-emul-boot
	@#-hard-disk-boot

init:	build-deps
	@[ -d build/ ] || mkdir -p build/
	@[ -d root/boot/ ] || mkdir -p root/boot/

build-deps:
	@as -o /dev/null /dev/null || (echo "missing binutils" && false)
	@gcc --version > /dev/null || (echo "missing gcc" && false)
	@perl -v > /dev/null || (echo "missing perl" && false)
	@convert > /dev/null || (echo "missing imagemagic" && false)
	@genisoimage --version > /dev/null || (echo "missing genisoimage" && false)

clean:
	@echo "  CLEAN"
	@[ -d build ] && rm -rf build || true
	@[ -f os.iso ] && rm os.iso || true
	@[ -d root/boot/ ] && rm -rf root/boot/ || true
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

.PHONY: bootloader
bootloader: build/boot.bin

build/boot.bin:
	$(call MAKE,bootloader)

.PHONY: kernel
kernel: build/kernel.bin build/kernel.reloc build/kernel.sym build/kernel.stabs

build/kernel.bin: fonts build/coff.exe
	$(call MAKE,kernel) && mv kernel/kernel.bin $@

build/kernel.reloc: $(KERNEL_OBJ) util/reloc.pl Makefile
	@# -C -R # 32 bit alpha unsupported.
	@echo "  RELOC $@"
	@util/reloc.pl $(KERNEL_OBJ).r build/kernel.reloc

build/kernel.sym: $(KERNEL_OBJ) util/symtab.pl Makefile
	@echo "  SYM   $@"
	@util/symtab.pl $(KERNEL_OBJ) build/kernel.sym

build/kernel.stabs: $(KERNEL_OBJ) util/stabs.pl Makefile
	@echo "  STABS $@"
	@util/stabs.pl -C $(KERNEL_OBJ) build/kernel.stabs

.PHONY: fonts
fonts:
	$(call MAKE,fonts)


# Utility - Build Assistance

util:	init build/write.exe build/asm.exe build/malloc.exe

build/write.exe: util/write.cpp
	@echo "  C     $@"
	@$(GCC) $< -o $@

build/malloc.exe: util/malloc.cpp
	@echo "  C     $@"
	@g++ -std=c++0x -o $@ $<

build/font.exe: util/font.cpp
	@echo "  C     $@"
	@gcc -x c -std=c99 $< -o $@

build/coff.exe: util/coff.cpp
	@echo "  C     $@"
	@g++ -std=c++0x -o $@ $<

##########################################################################

site:	site-init site-download site-doc www-neonics

site-init:
	@[ -d root/www/download ] || mkdir -p root/www/download
	@[ -f root/www/download/boot.img.gz ] && rm root/www/download/boot.img.gz || true
	@[ -f root/www/download/os.iso.gz ] && rm root/www/download/os.iso.gz || true

site-download: os.iso.tmp.gz
	@mv os.iso.tmp.gz root/www/download/os.iso.gz

os.iso.tmp.gz: site-init
	@echo "  ISO   $@"
	@cp --sparse=always build/boot.img root/boot/boot.img
	@#gzip build/boot.img -c > root/www/download/boot.img.gz
	@genisoimage -P Neonics -quiet -input-charset utf-8 -o os.iso.tmp \
		-r -b boot/boot.img \
		$(ISO_ARGS) \
		root/ && gzip -9 os.iso.tmp

site-src:
	#[ -d root/src/kernel ] || mkdir -p root/src/kernel
	#cp -a TODO Makefile 16 bootloader kernel util fonts root/src/kernel
DOC=Bootsector Cluster NetFork CloudNet
DOC_SRC=$(addprefix DOC/, $(addsuffix .txt,${WWW_DOC}))
WWW_DOC=$(addprefix root/www/doc/, $(addsuffix .html,${DOC}))

root/www/doc/%.html: DOC/%.txt util/txt2html.pl Makefile
	@[ -d root/www/doc ] || mkdir root/www/doc
	@echo "  HTML  $@"
	@util/txt2html.pl $< | xmllint - > $@

root/www/doc.inc: $(WWW_DOC)

site-doc: root/www/doc.inc
	@#[ -d root/src/kernel/DOC ] || mkdir -p root/src/kernel/DOC
	@#[ -d root/www/screenshots ] || mkdir -p root/www/screenshots
	@#cp -a DOC/Screenshots/*.png root/www/screenshots/
	@#cp DOC/* root/src/kernel/DOC/

root/www/doc.inc: $(WWW_DOC)
	@echo "  HTMLl $@"
	@ls root/www/doc | util/genlinks.pl > root/www/doc.inc

WWW_N = root/www/www.neonics.com

www-neonics:
	@[ -d web/www.neonics.com ] && ( \
	cd web/www.neonics.com && cpio --quiet -W none -d -p < .list ../../$(WWW_N)/ >& /dev/null ) || true


site-clean:
	rm -rf root/www/screenshots root/www/download root/src/
