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

CODE_ISO_DEPS = root/boot/boot.img

DATA_ISO_DEPS = $(shell find root/ -type f|grep -v www/download/os.iso.gz) \
	root/boot/boot.img

.PHONY: foo
foo:
	@echo $(ISO_DEPS)


os.iso: SECTORS = $(call CALC_SECTORS,build/boot.img)
os.iso: $(CODE_ISO_DEPS) root/ | init
	@#cp --sparse=always build/boot.img root/boot/boot.img
	@echo "  ISO   $@"
	@genisoimage -P Neonics -quiet -input-charset utf-8 -o os.iso.tmp \
		-r -b boot/boot.img \
		$(ISO_ARGS) \
		root/ && cp --sparse=always os.iso.tmp os.iso && rm os.iso.tmp
	@#-J -boot-info-table
	@#-no-emul-boot
	@#-hard-disk-boot

data.iso: $(DATA_ISO_DEPS) root/www/download/os.iso.gz | init site


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
		-s 2880 \
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
build/kernel.bin: FORCE fonts build/coff.exe util
	$(call MAKE,kernel) && cp -u kernel/kernel.bin $@

build/kernel.reloc: $(KERNEL_OBJ) util/reloc.pl Makefile
	@# -C -R # 32 bit alpha unsupported.
	@echo "  RELOC $@"
	@util/reloc.pl --no-16 $(KERNEL_OBJ).r build/kernel.reloc

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

util:	init build/write.exe build/malloc.exe build/symtab.exe

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

build/symtab.exe: util/symtab.cpp
	@echo "  C     $@"
	@g++ -std=c++0x -o $@ $<

##########################################################################

#	root/www/download/os.iso.gz

.PHONY: site-init site www-neonics site-check

site:	site-init site-doc www-neonics site-check
	touch root

site-check:
	@echo "  LINKCHK"
	@util/linkchecker.pl root/www/doc/

site-init:
	@[ -d root/www/download ] || mkdir -p root/www/download || true
	@#[ -f root/www/download/boot.img.gz ] && rm root/www/download/boot.img.gz || true
	@#[ -f root/www/download/os.iso.gz ] && rm root/www/download/os.iso.gz || true

root/www/download/os.iso.gz: $(ISO_DEPS) | site-init
	@echo "  ISO   $@"
	@[ -f root/www/download/os.iso.gz ] && rm root/www/download/os.iso.gz || true
	@#gzip build/boot.img -c > root/www/download/boot.img.gz
	touch root/www/download/os.iso.gz
	#@genisoimage -P Neonics -quiet -input-charset utf-8 -o os.iso.site \
	#	-r -b boot/boot.img \
	#	$(ISO_ARGS) \
	#	root/ && gzip -9 os.iso.site \
	#	&& mv os.iso.site.gz root/www/download/os.iso.gz

TXTDOC=$(shell util/doctools.pl -d DOC/ -t txt list)
HTMLDOC=$(shell util/doctools.pl -d DOC/ -t html list)

WWW_DOC=$(addprefix root/www/doc/, $(addsuffix .html,${TXTDOC}))
DOC_SRC=$(addprefix DOC/, $(addsuffix .txt,${WWW_DOC}))
HTML_DOC=$(addprefix root/www/doc/, $(addsuffix .html,${HTMLDOC})) \
	root/www/doc/menu.xml root/www/doc/src/menu.xml

HTMLDEPS = util/template.pl util/template.html util/Template.pm Makefile

root/www/doc/%.html: RP = $(shell echo $(patsubst %,../,$(subst /, ,$(dir $<)))|sed -e 's/ //g')www.neonics.com/
root/www/doc/%.html: DOC/%.txt util/txt2html.pl $(HTMLDEPS)
	@[ -d root/www/doc ] || mkdir root/www/doc
	@[ -d root/www/doc/notes ] || mkdir root/www/doc/notes
	@echo "  HTML  $@"
	@util/txt2html.pl \
		--rawtitle $(lastword $(subst /, ,$<)) \
		-t util/template.html \
		-p ${RP} \
		--onload "template( null, '${RP}', [], 'menu.xml');" \
		$< > $@

root/www/doc/%.html: RP = $(shell echo $(patsubst %,../,$(subst /, ,$(dir $<)))|sed -e 's/ //g')www.neonics.com/
root/www/doc/%.html: DOC/%.html $(HTMLDEPS)
	@echo "  HTML  $@"
	@util/template.pl -t util/template.html -p ${RP} --toc --menuxml menu.xml $< > $@

root/www/doc/menu.xml: root/www/doc-menu.xml
	@cp $< $@

root/www/doc/src/menu.xml: root/www/doc-src-menu.xml
	@[ -d root/www/doc/src ] || mkdir root/www/doc/src
	@cp $< $@

site-doc: root/www/doc.inc root/www/doc/index.html
	@#[ -d root/src/kernel/DOC ] || mkdir -p root/src/kernel/DOC
	@#[ -d root/www/screenshots ] || mkdir -p root/www/screenshots
	@#cp -a DOC/Screenshots/*.png root/www/screenshots/
	@#cp DOC/* root/src/kernel/DOC/

site-src:
	make -s --no-print-directory -C kernel ../root/www/doc/src/src.ref

root/www/doc.inc: $(WWW_DOC) $(HTML_DOC) util/doctools.pl DOC/.index
	@echo "  HTMLl $@"
	@#ls root/www/doc | grep -v -e \.xml\$$ | util/genlinks.pl > root/www/doc.inc
	@util/doctools.pl -d DOC genlinks --tree --mtime --maxhours '7*24' --relpath doc/ > $@

root/www/doc/index.html: root/www/doc.inc
	@echo "  HTML  $@"
	@cat $< | sed -e 's@doc/@@g' | \
	util/template.pl -t util/template.html -p ../www.neonics.com/ \
		--menuxml 'menu.xml' - > $@

WWW_N = root/www/www.neonics.com

WWW_N_SRC=$(patsubst %,web/www.neonics.com/%,\
	$(shell [ -d web/www.neonics.com ] && cat web/www.neonics.com/.list | xargs ))

www-neonics: $(WWW_N_SRC)
	@echo "  SITE  www.neonics.com"
	@[ -d web/www.neonics.com ] && ( \
	make -s --no-print-directory -C web/www.neonics.com ; \
	cd web/www.neonics.com && \
	cpio --quiet -W none -d -p < .list ../../$(WWW_N)/ >& /dev/null \
	) || true


site-clean:
	@rm -rf root/www/screenshots root/www/download root/www/doc/ root/src/

.PHONY: FORCE
FORCE: ;
