all: kernel.bin Makefile

clean:
	rm -f kernel.bin kernel.obj kernel.stabs kernel.sym kernel.dep \
		kernel.obj.r kernel.obj.reloc.txt kernel.obj.map \
		kernel.o ring2.o \
		|| true
	@make -C fs/oofs $@

# attempt to link multiple object files
KERNEL_SPLIT_RINGS=1

GIT = /usr/bin/git	# i have a wrapper script in my path

AS_DEFS = --defsym __KERNEL_SPLIT_RINGS=$(KERNEL_SPLIT_RINGS)

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
	--no-leading-underscore --no-undefined --no-demangle --no-define-common \
	--warn-section-align

KERNEL_OBJECTS = kernel.o fs/oofs/oofs.o

ifeq ($(KERNEL_SPLIT_RINGS),1)
KERNEL_OBJECTS += ring2.o
LD = ld $(LD_OPTS) #-r
else
#LD = cp $< $@
LD = ld $(LD_OPTS) #-r
endif

# a fixup routine that adjusts the size for the section headers of structures.
# I have not found a way to specify section padding to AS, nor to change it
# using objcopy or ld. The trouble is that AS has already padded the section
# to a dword boundary, and thus records more data than the section actually
# contains.
define FIXUP
	@echo "  FIXUP $1"
	@../build/coff $1 --remove-padding .shellcmd 10
endef


kernel.bin: kernel.obj
	@echo "   OBJ  $@"
	objcopy -O binary -j .text $< $@

kernel.obj: $(KERNEL_OBJECTS) kernel.link
	@echo "   LD $@ <- $^"

		# produce relocatable obj with sections
		@ld $(LD_OPTS) \
			--script kernel.link-sections \
			-Map $@.map \
			--image-base 0 \
			-r \
			$(KERNEL_OBJECTS) \
			-o $@0.r

		# link the one with sections
		@ld $(LD_OPTS) \
			--script kernel.link \
			-Map $@.obj0.map \
			--image-base 0 \
			-o $@0 $@0.r

	@#first with -r to catch relocation info
	@ld $(LD_OPTS) \
		--script kernel.link \
		-Map $@.map \
		--image-base 0 \
		-r \
		$(KERNEL_OBJECTS) \
		-o $@.r
	@#objdump -r -j .text $@.r > $@.reloc.txt

	@ld $(LD_OPTS) \
		--script kernel.link \
		-Map $@.map \
		--image-base 0 \
		-o $@ $(KERNEL_OBJECTS) #$^

KLIB_SRC = lib/mem.s lib/mem_handle.s \
		lib/ll.s lib/string.s lib/buffer.s lib/token.s

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
	pmode.s pic.s gdt.s idt.s tss.s \
	schedule.s \
	mutex.s console.s paging.s

HARDWARE_SRC = keyboard.s keycodes.s pit.s pci.s bios.s cmos.s ata.s dma.s \
	nic.s dev.s $(USB_SRC) $(NIC_SRC) $(VMWARE_SRC) $(VBOX_SRC) \
	$(BRIDGE_SRC) $(SOUND_SRC)

DBG_SRC = debugger/export.s debugger/debugger.s debugger/hwdebug.s

SOUND_SRC = sound/sb.s sound/es1371.s

USB_SRC = usb/usb.s usb/usb_ohci.s

VMWARE_SRC = vmware/vmware.s vmware/bdoor.s vmware/chan.s vmware/vix.s \
	vmware/svga2.s

VBOX_SRC = vbox/vbva.s vbox/vbga.s

BRIDGE_SRC = pcibridge/i440.s pcibridge/ipiix4.s

NIC_SRC = nic/rtl8139.s nic/i8254.s nic/am79c971.s

NET_SRC = net/*.s

FS_SRC = fs.s partition.s fs/iso9660.s fs/fat.s fs/sfs.s fs/fs_oofs.s

GFX_SRC = gfx.s ../fonts/courier56.s

LIB_SRC = ../lib/sha.s ../lib/base64.s ../lib/xml.s ../lib/browser.s

ring0.o: ring0.s
	@echo "   AS   $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

ring1.o: ring1.s
	@echo "   AS   $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

ring2.o: ring2.s defines.s macros.s $(DBG_SRC) print.s \
		gdt.s mutex.s oo.s schedule.s \
		lib/hash.s \
		kapi/export.h \
		dev.s \
		pci.s pic.s dma.s ata.s \
		shell.s keycodes.s fs.s partition.s \
		$(SOUND_SRC) \
		$(VMWARE_SRC) $(VBOX_SRC) \
		$(BRIDGE_SRC) \
		$(USB_SRC) \
		nic.s $(NIC_SRC) \
		$(NET_SRC)
	@echo "   AS   $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

ring3.o: ring3.s
	@echo "   AS   $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

kernel.o: $(KERNEL_SRC) $(HARDWARE_SRC) acpi.s \
		$(FS_SRC) $(NET_SRC) $(GFX_SRC) \
		$(LIB_SRC) \
		shell.s Makefile
	@echo "   AS   $@"
	@$(AS) -o $@ $<
	@$(call FIXUP,$@)

fs/fs_oofs.s: fs/oofs/export.h

fs/oofs/oofs.o: FORCE kapi/export.h export.h
	@echo " M $@"
	@make -C fs/oofs

export.h: BRANCH=$(shell $(GIT) branch | grep -e ^\* | cut -b3-)
export.h: KERNEL_REVISION=$(shell $(GIT) log --pretty=oneline --abbrev-commit | wc -l)
export.h: kernel.o Makefile ../.git
	@echo "   H    $@"
	grep -e "^\.equ SEL_" gdt.s \
	| perl -pe 's/^\.equ SEL_(\S+),(.*)/SEL_\1=\2/' \
	> export.h
	echo "BRANCH=`git branch | grep -e ^\* | cut -b3-`" \
	>> export.h
	echo "KERNEL_REVISION=$(KERNEL_REVISION)" \
	>> export.h
	@echo ".macro LOAD_KERNEL_VERSION_TXT reg:vararg;LOAD_TXT \"$(BRANCH)-$(KERNEL_REVISION)\",\reg;.endm" \
	>> export.h


kapi/export.h: kernel.o Makefile
	@echo ".include \"kapi/kapi.s\"" > $@
	@echo "_KAPI_COUNTER=`nm $< | grep ' A KAPI_' | wc -l`" >> $@

.PHONY: FORCE
FORCE: ;
