all: kernel.bin Makefile

clean:
	[ -f kernel.bin ] && /bin/rm kernel.bin || true
	[ -f kernel.o ] && /bin/rm kernel.o || true

AS = /bin/as -R -n --warn --fatal-warnings

kernel.bin: kernel.o
	../util/checksymbols $<
	objcopy -O binary $< $@

KERNEL_SRC = kernel.s debug.s debugger.s realmode.s print.s \
	pmode.s pic.s gdt.s idt.s tss.s \
	mem.s hash.s list.s string.s

HARDWARE_SRC = keyboard.s keycodes.s pit.s pci.s bios.s cmos.s ata.s \
	nic.s rtl8139.s i8254.s dev.s gfx.s

NET_SRC = net.s

FS_SRC = fs.s iso9660.s partition.s fat.s sfs.s


kernel.o: $(KERNEL_SRC) $(HARDWARE_SRC) acpi.s $(FS_SRC) $(NET_SRC) \
		token.s shell.s
	$(AS) -o $@ $<
	../util/checksymbols $@
