all: kernel.bin

clean:
	[ -f kernel.bin ] && /bin/rm kernel.bin || true
	[ -f kernel.o ] && /bin/rm kernel.o || true

AS = /bin/as -R -n --warn --fatal-warnings

kernel.bin: kernel.o
	../util/checksymbols $<
	objcopy -O binary $< $@

kernel.o: kernel.s debug.s realmode.s print.s pmode.s pic.s gdt.s idt.s tss.s \
		keyboard.s keycodes.s pit.s \
		pci.s bios.s cmos.s acpi.s
	$(AS) -o $@ $<
	../util/checksymbols $@
