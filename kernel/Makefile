all: kernel.bin Makefile

clean:
	rm -f kernel.bin kernel.obj kernel.stabs kernel.sym kernel.dep \
		kernel.obj.r kernel.obj.reloc.txt kernel.obj.map \
		kernel.o ring2.o \
		|| true

# attempt to link multiple object files
KERNEL_SPLIT_RINGS=1


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

ifeq ($(KERNEL_SPLIT_RINGS),1)
KERNEL_OBJECTS = kernel.o ring2.o fs/oofs/oofs.o
LD = ld $(LD_OPTS) -r
else
KERNEL_OBJECTS = kernel.o fs/oofs/oofs.o
LD = cp $< $@
LD = ld $(LD_OPTS) -r
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

KERNEL_SRC = kernel.s defines.s macros.s debug.s oo.s debugger.s \
	ring2.s \
	$(EXE_SRC) \
	$(KLIB_SRC) \
	$(KAPI_SRC) \
	realmode.s print.s \
	pmode.s pic.s gdt.s idt.s tss.s \
	schedule.s hwdebug.s \
	mutex.s console.s paging.s

HARDWARE_SRC = keyboard.s keycodes.s pit.s pci.s bios.s cmos.s ata.s dma.s \
	nic.s dev.s $(USB_SRC) $(NIC_SRC) $(VMWARE_SRC) $(VBOX_SRC) \
	$(BRIDGE_SRC) $(SOUND_SRC)

SOUND_SRC = sound/sb.s sound/es1371.s

USB_SRC = usb/usb.s usb/usb_ohci.s

VMWARE_SRC = vmware/vmware.s vmware/bdoor.s vmware/chan.s vmware/vix.s \
	vmware/svga2.s

VBOX_SRC = vbox/vbva.s vbox/vbga.s

BRIDGE_SRC = pcibridge/i440.s pcibridge/ipiix4.s

NIC_SRC = nic/rtl8139.s nic/i8254.s nic/am79c971.s

NET_SRC = net/*.s

FS_SRC = fs.s partition.s fs/iso9660.s fs/fat.s fs/sfs.s

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

ring2.o: ring2.s defines.s macros.s debug.s print.s \
		gdt.s mutex.s oo.s schedule.s \
		lib/hash.s \
		$(KAPI_SRC) \
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


fs/oofs/oofs.o: fs/oofs/*.s fs/oofs/Makefile
	@echo " M $@"
	@make -C fs/oofs
