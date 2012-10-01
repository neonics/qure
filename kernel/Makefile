all: kernel.bin Makefile

clean:
	[ -f kernel.bin ] && /bin/rm kernel.bin || true
	[ -f kernel.o ] && /bin/rm kernel.o || true

AS = /bin/as -R -n --warn --fatal-warnings

kernel.bin: kernel.o
	@../util/checksymbols $<
	@echo "   OBJ  $@"
	@objcopy -O binary $< $@

KERNEL_SRC = kernel.s macros.s debug.s debugger.s realmode.s print.s \
	pmode.s pic.s gdt.s idt.s tss.s \
	mem.s hash.s list.s string.s

HARDWARE_SRC = keyboard.s keycodes.s pit.s pci.s bios.s cmos.s ata.s \
	nic.s dev.s $(NIC_SRC)

NIC_SRC = rtl8139.s i8254.s am79c971.s

NET_SRC = net.s

FS_SRC = fs.s iso9660.s partition.s fat.s sfs.s

GFX_SRC = gfx.s ../fonts/courier56.s

kernel.o: $(KERNEL_SRC) $(HARDWARE_SRC) acpi.s $(FS_SRC) $(NET_SRC) $(GFX_SRC) \
		token.s shell.s
	@echo "   AS   $@"
	@$(AS) -o $@ $<
	@../util/checksymbols $@
