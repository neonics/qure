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
	--no-leading-underscore --no-undefined --no-demangle --no-define-common

ifeq ($(KERNEL_SPLIT_RINGS),1)
KERNEL_OBJECTS = kernel.o ring2.o
LD = ld $(LD_OPTS) -r
else
KERNEL_OBJECTS = kernel.o
LD = cp $< $@
LD = ld $(LD_OPTS) -r
endif


kernel.bin: kernel.obj
	@echo "   OBJ  $@"
	objcopy -O binary -j .text $< $@

kernel.obj: $(KERNEL_OBJECTS) kernel.link
	@echo "   LD $@ <- $^"
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

KERNEL_SRC = kernel.s defines.s macros.s debug.s oo.s debugger.s kapi*.s \
	ring2.s \
	realmode.s print.s \
	pmode.s pic.s gdt.s idt.s tss.s \
	mem.s mem_handle.s hash.s list.s ll.s string.s schedule.s hwdebug.s \
	elf.s pe.s libc.s \
	mutex.s console.s paging.s buffer.s

HARDWARE_SRC = keyboard.s keycodes.s pit.s pci.s bios.s cmos.s ata.s dma.s \
	nic.s dev.s $(USB_SRC) $(NIC_SRC) $(VMWARE_SRC) $(VBOX_SRC) $(INTEL_SRC) \
	sb.s es1371.s

USB_SRC = usb.s usb_ohci.s

VMWARE_SRC = vmware/vmware.s vmware/bdoor.s vmware/chan.s vmware/vix.s \
	vmware/svga2.s

VBOX_SRC = vbox/vbva.s vbox/vbga.s

INTEL_SRC = i440.s ipiix4.s # i8254.s

NIC_SRC = rtl8139.s i8254.s am79c971.s

NET_SRC = net/*.s

FS_SRC = fs.s iso9660.s partition.s fat.s sfs.s

GFX_SRC = gfx.s ../fonts/courier56.s

LIB_SRC = ../lib/sha.s ../lib/base64.s ../lib/xml.s ../lib/browser.s

ring0.o: ring0.s
	@echo "   AS   $@"
	@$(AS) -o $@ $<

ring1.o: ring1.s
	@echo "   AS   $@"
	@$(AS) -o $@ $<

ring2.o: ring2.s defines.s macros.s print.s oo.s kapi.s hash.s pci.s gdt.s \
		debug.s pic.s mutex.s fs.s shell.s dev.s nic.s $(NIC_SRC) \
		$(NET_SRC) $(VMWARE_SRC) $(VBOX_SRC) $(USB_SRC) $(INTEL_SRC)
	@echo "   AS   $@"
	@$(AS) -o $@ $<

ring3.o: ring3.s
	@echo "   AS   $@"
	@$(AS) -o $@ $<

kernel.o: $(KERNEL_SRC) $(HARDWARE_SRC) acpi.s $(FS_SRC) $(NET_SRC) $(GFX_SRC) \
		$(LIB_SRC) \
		token.s shell.s Makefile
	@echo "   AS   $@"
	@$(AS) -o $@ $<
