all: kernel.bin Makefile

clean:
	/bin/rm -f kernel.bin kernel.o kernel.stabs kernel.sym || true

AS = as -march=i686 -R -n --warn --fatal-warnings --gstabs --MD kernel.dep

kernel.bin: kernel.o
	@../util/checksymbols $<
	@echo "   OBJ  $@"
	@objcopy -O binary -R .strtab $< $@

KERNEL_SRC = kernel.s defines.s macros.s debug.s oo.s debugger.s \
	realmode.s print.s \
	pmode.s pic.s gdt.s idt.s tss.s \
	mem.s mem_handle.s hash.s list.s ll.s string.s schedule.s hwdebug.s \
	elf.s libc.s \
	mutex.s console.s paging.s buffer.s

HARDWARE_SRC = keyboard.s keycodes.s pit.s pci.s bios.s cmos.s ata.s dma.s \
	nic.s dev.s usb.s usb_ohci.s $(NIC_SRC) $(VMWARE_SRC) $(VBOX_SRC) $(INTEL_SRC) \
	sb.s es1371.s

VMWARE_SRC = vmware/vmware.s vmware/bdoor.s vmware/chan.s vmware/vix.s \
	vmware/svga2.s

VBOX_SRC = vbox/vbva.s vbox/vbga.s

INTEL_SRC = i440.s ipiix4.s # i8254.s

NIC_SRC = rtl8139.s i8254.s am79c971.s

NET_SRC = net/*.s

FS_SRC = fs.s iso9660.s partition.s fat.s sfs.s

GFX_SRC = gfx.s ../fonts/courier56.s

LIB_SRC = ../lib/sha.s ../lib/base64.s ../lib/xml.s ../lib/browser.s

kernel.o: $(KERNEL_SRC) $(HARDWARE_SRC) acpi.s $(FS_SRC) $(NET_SRC) $(GFX_SRC) \
		$(LIB_SRC) \
		token.s shell.s Makefile
	@echo "   AS   $@"
	@$(AS) -o $@ $<
	@../util/checksymbols $@
