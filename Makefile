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


.PHONY: all clean init build-deps site

all: os.iso

ISO_DEPS = $(shell find root/ -type f|grep -v www/download/os.iso.gz) \
	root/boot/boot.img

os.iso: SECTORS = $(call CALC_SECTORS,build/boot.img)
os.iso: $(ISO_DEPS) root/www/download/os.iso.gz | init site
	@#cp --sparse=always build/boot.img root/boot/boot.img
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

clean: site-clean
	@echo "  CLEAN"
	@[ -d build ] && rm -rf build || true
	@[ -f os.iso ] && rm os.iso || true
	@[ -d root/boot/ ] && rm -rf root/boot/ || true
	$(call MAKE,bootloader,clean)
	$(call MAKE,kernel,clean)
	$(call MAKE,fonts,clean)

root/boot/boot.img: build/boot.img
	@echo "  COPY  $< $@"
	@cp --sparse=always build/boot.img root/boot/boot.img

BOOT_DEPS = build/boot.bin build/kernel.bin build/kernel.reloc \
	build/kernel.sym build/kernel.stabs

build/boot.img: $(BOOT_DEPS) build/write.exe
	@echo "  BOOT  $@"
	@build/write.exe -o $@ \
		-b build/boot.bin \
		-rd \
		-b build/kernel.bin \
		-b build/kernel.reloc \
		-b build/kernel.sym \
		-b build/kernel.stabs \
	&& chmod 644 $@

# bootloader
build/boot.bin: FORCE | init
	$(call MAKE,bootloader) && cp -u bootloader/boot.bin $@

# kernel
build/kernel.bin: FORCE fonts build/coff.exe
	$(call MAKE,kernel) && cp -u kernel/kernel.bin $@

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

#	root/www/download/os.iso.gz

.PHONY: site-init site www-neonics

site:	site-init site-doc www-neonics


site-init:
	@[ -d root/www/download ] || mkdir -p root/www/download || true
	@#[ -f root/www/download/boot.img.gz ] && rm root/www/download/boot.img.gz || true
	@#[ -f root/www/download/os.iso.gz ] && rm root/www/download/os.iso.gz || true

root/www/download/os.iso.gz: $(ISO_DEPS) | site-init
	@echo "  ISO   $@"
	@[ -f root/www/download/os.iso.gz ] && rm root/www/download/os.iso.gz || true
	@#gzip build/boot.img -c > root/www/download/boot.img.gz
	@genisoimage -P Neonics -quiet -input-charset utf-8 -o os.iso.site \
		-r -b boot/boot.img \
		$(ISO_ARGS) \
		root/ && gzip -9 os.iso.site \
		&& mv os.iso.site.gz root/www/download/os.iso.gz

site-src:
	#[ -d root/src/kernel ] || mkdir -p root/src/kernel
	#cp -a TODO Makefile 16 bootloader kernel util fonts root/src/kernel

DOC=Bootsector Cluster NetFork CloudNet LiquidChristalProcessor CircularBuffer \
	HostMe Freedom Net TaskSwitching CallingConvention Filesystem \
	EnclosedSource DNS2

DOC_SRC=$(addprefix DOC/, $(addsuffix .txt,${WWW_DOC}))
WWW_DOC=$(addprefix root/www/doc/, $(addsuffix .html,${DOC}))

root/www/doc/%.html: DOC/%.txt util/txt2html.pl
	#Makefile
	@[ -d root/www/doc ] || mkdir root/www/doc
	@echo "  HTML  $@"
	@#util/txt2html.pl -t web/doc.htmlt $< | xmllint - > $@
	@echo '$${CONTENT}' > _tmp_template.html
	@util/txt2html.pl -t none $< > $@.tmp
	@util/template.pl -t util/template.html -p ../www.neonics.com/ $@.tmp > $@
	@rm _tmp_template.html $@.tmp

site-doc: root/www/doc.inc
	@#[ -d root/src/kernel/DOC ] || mkdir -p root/src/kernel/DOC
	@#[ -d root/www/screenshots ] || mkdir -p root/www/screenshots
	@#cp -a DOC/Screenshots/*.png root/www/screenshots/
	@#cp DOC/* root/src/kernel/DOC/

root/www/doc.inc: $(WWW_DOC)
	@echo "  HTMLl $@"
	@ls root/www/doc | util/genlinks.pl > root/www/doc.inc

WWW_N = root/www/www.neonics.com

WWW_N_SRC=$(patsubst %,web/www.neonics.com/%,\
	$(shell [ -d web/www.neonics.com ] && cat web/www.neonics.com/.list | xargs ))

www-neonics: $(WWW_N_SRC)
	@echo "  SITE  www.neonics.com"
	@[ -d web/www.neonics.com ] && ( \
	cd web/www.neonics.com && cpio --quiet -W none -d -p < .list ../../$(WWW_N)/ >& /dev/null ) || true


site-clean:
	@rm -rf root/www/screenshots root/www/download root/src/

.PHONY: FORCE
FORCE: ;
