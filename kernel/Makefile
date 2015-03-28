all: kernel.bin Makefile 

# srcref

clean:
	@echo "  CLEAN"
	@rm -rf kernel.bin kernel.obj kernel.stabs kernel.sym kernel.dep \
		kernel.obj* \
		kernel.o ring2.o ring2_.o export.h kapi/export.h \
		../root/www/doc/src/ \
		_empty_ _empty_.s \
		|| true
	@echo "  CLEAN fs/oofs"
	@make -s -C fs/oofs $@

# attempt to link multiple object files
KERNEL_SPLIT_RINGS=1

GIT = /usr/bin/git	# i have a wrapper script in my path

IS_ELF = $(shell touch _empty_.s && as -o _empty_ _empty_.s && file _empty_ | grep -c ELF )

AS_DEFS = # --defsym __KERNEL_SPLIT_RINGS=$(KERNEL_SPLIT_RINGS)
AS_DEFS = --defsym ELF=$(IS_ELF)

# i486 due to bswap (and cmpxchg)
AS = as --32 -march=i486 -n --warn --fatal-warnings --gstabs --MD kernel.dep $(AS_DEFS)
# rdtsc requires Pentium I (i586) 
#AS = as --32 -march=i586 -R -n --warn --fatal-warnings --gstabs --MD kernel.dep
# sysenter requires Pentium II (i686) 
#AS = as --32 -march=i686 -R -n --warn --fatal-warnings --gstabs --MD kernel.dep

# AS options:
# -n: do not optimize code alignment
# -R: fold .data into .text

# LD options:
# -r/-i/--relocatable: produce relocatable output
#  --embedded-relocs (relocation info embedded in sections for COFF)
# -q/--emit-relocs: generate/leave relocs in final output (.reloc section)
# -verbose [=level]  shows linker script (section definitions)
# --cref: cross reference (symbol and which obj files declare it)
# --noinhibit-exec: produce target object file even if errors
LD_OPTS = -nostartfiles -nodefaultlibs -nostdlib --exclude-libs ALL \
	--no-undefined --no-demangle --no-define-common \
	--warn-section-align

KERNEL_OBJECTS = kernel.o ring2.o


ifeq ($(IS_ELF),1)
FIXUP_CMD = echo "WARNING - skip fixup: not supported on ELF yet"
LD_OPTS += -m elf_i386
else
FIXUP_CMD = ../build/coff.exe $1 --remove-padding .shellcmd 10
LD_OPTS += --no-leading-underscore
endif

# a fixup routine that adjusts the size for the section headers of structures.
# I have not found a way to specify section padding to AS, nor to change it
# using objcopy or ld. The trouble is that AS has already padded the section
# to a dword boundary, and thus records more data than the section actually
# contains.
define FIXUP
	@echo "  FIXUP $1"
	@$(FIXUP_CMD)
	@#../build/coff.exe $1 --remove-padding .shellcmd 10
endef


# For ELF hosts only:
define MAKE_COFF
	@echo "  ELF2COFF $1"
	@mv $1 $1.orig
	@objcopy -O pei-i386 --debug --keep-file-symbols --localize-hidden $1.orig $1
endef


kernel.bin: kernel.obj
	@echo "  OBJ   $@"
	@objcopy -O binary -j .text $< $@

kernel.obj: $(KERNEL_OBJECTS) kernel.link
	@echo "  LD    $@ <- $^"

	@ld $(LD_OPTS) \
		--script kernel.link \
		-Map $@.map \
		-r \
		$(KERNEL_OBJECTS) \
		-o $@.r
	@#objdump -r -j .text $@.r > $@.reloc.txt

ifeq ($(IS_ELF),1)
	@$(call MAKE_COFF,$@.r)
endif

	@#hack: we use kernel.obj.r and link it ourselves:
	@cp $@.r $@ && ../build/coff.exe $@ --link .text

	@# check symbols:
	@echo "  CHKSYM $@"
	@nm -u $@ | grep -v .text16 | wc -l | perl -ne 'chomp; /^\s*0\s*/ or die "$$_ undefined symbols:\n", `nm -u $@ | grep -v .text16 `'

	@# create debug version
	@objcopy --change-addresses 0x13000 --debugging kernel.obj kernel.obj.debug

	@#update stabs
	@../build/coff.exe kernel.obj.debug --adjust-source 0x13000


KLIB_SRC = lib/mem.s lib/handles.s \
		lib/ll.s lib/string.s lib/buffer.s lib/token.s lib/hash.s

EXE_SRC = exe/libc.s exe/elf.s exe/pe.s

KAPI_SRC = kapi/kapi*.s

KERNEL_SRC = kernel.s defines.s macros.s \
		$(DBG_SRC) \
		oo.s	\
	ring2.s \
	$(EXE_SRC) \
	$(KLIB_SRC) \
	$(KAPI_SRC) \
	realmode.s print.s \
	pmode.s pic.s gdt.s idt.s tss.s ../16/pmode.s \
	schedule.s \
	mutex.s console.s paging.s

HARDWARE_SRC = keyboard.s keycodes.s pit.s pci.s bios.s cmos.s ata.s dma.s \
	uart.s \
	nic.s dev.s \
	$(USB_SRC) $(NIC_SRC) $(VMWARE_SRC) $(VBOX_SRC) \
	$(BRIDGE_SRC) $(SOUND_SRC)

DBG_SRC = debugger/export.s debugger/debugger.s debugger/hwdebug.s

SOUND_SRC = sound/sb.s sound/es1371.s sound/ac97.s

USB_SRC = usb/usb.s usb/usb_ohci.s

VMWARE_SRC = vmware/vmware.s vmware/bdoor.s vmware/chan.s vmware/vix.s \
	vmware/svga2.s

VBOX_SRC = vbox/vbva.s vbox/vbga.s

BRIDGE_SRC = pcibridge/i440.s pcibridge/ipiix4.s

NIC_SRC = nic/rtl8139.s nic/i8254.s nic/am79c971.s nic/bcm57xx.s

NET_SRC = net/*.s

FS_API_SRC = fs.s partition.s

FS_IMPL_SRC = fs/iso9660.s fs/fat.s fs/sfs.s fs/fs_oofs.s

GFX_SRC = gfx.s gfx_vbe.s ../fonts/courier56.s

LIB_SRC = ../lib/sha.s ../lib/base64.s ../lib/xml.s ../lib/browser.s \
	../lib/crc32.s ../lib/gzip.s ../lib/aes.s


RING2_SRC = ring2.s defines.s macros.s $(DBG_SRC) print.s \
		gdt.s mutex.s oo.s schedule.s \
		lib/hash.s \
		export.h \
		kapi/export.h \
		fs/oofs/export.h \
		dev.s \
		pci.s pic.s dma.s ata.s \
		shell.s keycodes.s \
		$(FS_IMPL_SRC) $(FS_API_SRC) \
		$(SOUND_SRC) \
		$(VMWARE_SRC) $(VBOX_SRC) \
		$(BRIDGE_SRC) \
		$(USB_SRC) \
		nic.s $(NIC_SRC) \
		$(NET_SRC)


ring0.o: ring0.s
	@echo "  AS   $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

ring1.o: ring1.s
	@echo "  AS   $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

ring2_.o: $(RING2_SRC)
	@echo "  AS    $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

ring2.o: ring2_.o fs/oofs/oofs.o
	@echo "  LD    $@"
	@$(LD) $(LD_OPTS) -r -o $@ $^
	@$(call FIXUP,$@)

ring3.o: ring3.s
	@echo "  AS    $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

kernel.o: $(KERNEL_SRC) $(HARDWARE_SRC) acpi.s \
		$(FS_API_SRC) $(NET_SRC) $(GFX_SRC) \
		$(LIB_SRC) \
		shell.s Makefile
	@echo "  AS    $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

fs/oofs/oofs.o fs/oofs/export.h: FORCE export.h kapi/export.h export.h
	@echo "  M     $@"
	@make -s -C fs/oofs

export.h: BRANCH=$(shell $(GIT) branch | grep -e ^\* | cut -b3-)
export.h: KERNEL_REVISION=$(shell $(GIT) log --pretty=oneline --abbrev-commit | wc -l)
export.h: kernel.o Makefile ../.git
	@echo "  H     $@"
	@grep -e "^\.equ SEL_" gdt.s \
	| perl -pe 's/^\.equ SEL_(\S+),(.*)/SEL_\1=\2/' \
	> $@
	@# disabled: will generate an undefined symbol for the branch name
	@#echo "BRANCH=`git branch | grep -e ^\* | cut -b3-`" \
	>> $@
	@echo "KERNEL_REVISION=$(KERNEL_REVISION)" \
	>> $@
	@echo ".macro LOAD_KERNEL_VERSION_TXT _reg:vararg;LOAD_TXT \"$(BRANCH)-$(KERNEL_REVISION)\",\_reg;.endm" \
	>> $@
	@# create file with constants: list absolute symbols.
	@#  (-g: only global/external symbols - speed)
	@nm -f bsd -g --defined-only $< \
	| grep ' A ' \
	| perl -ne 's/(\S+) . (\S+)/\2=0x\1/; print' \
	>> $@

kapi/export.h: kernel.o Makefile
	@echo ".include \"kapi/kapi.s\"" > $@
	@echo "_KAPI_COUNTER=`nm $< | grep ' A KAPI_' | wc -l`" >> $@


#################################################################################
# Source Reference

REFSRC = $(sort $(KERNEL_SRC) $(HARDWARE_SRC) acpi.s $(FS_API_SRC) $(NET_SRC) $(GFX_SRC) $(LIB_SRC) $(RING2_SRC))
REFDIR = ../root/www/doc/src

REFFILES = $(addprefix ${REFDIR}/, $(addsuffix .html, $(subst /,_,$(REFSRC))))

.PHONY: srcref
srcref: $(REFDIR) $(REFDIR)/src.ref $(REFFILES)

$(REFDIR):
	[ -d $@ ] || mkdir -p $@

$(REFFILES) $(REFDIR)/index.html: $(REFSRC)
$(REFDIR)/src.ref: $(REFSRC) | ../util/fmtsrc.pl $(REFDIR)
	#optional dep: ../util/Template.pm
	@echo "  REF   $?"
	@../util/fmtsrc.pl --dir ../root/www/doc/src/ \
		--srelpath .. \
		--index-header 'tree.inc' \
		--template ../util/template.html \
		-p ../../www.neonics.com/ \
		--title "Source Reference:" \
		--menuxml menu.xml \
		--tagline "Use The Source" \
		$?

#################################################################################

.PHONY: FORCE
FORCE: ;
