all: kernel.bin

clean:
	/bin/rm kernel.bin kernel.o

AS = /bin/as -R -n --warn --fatal-warnings

kernel.bin: kernel.o
	../util/checksymbols $<
	objcopy -O binary $< $@

kernel.o: kernel.s print.s pmode.s pic.s gdt.s idt.s tss.s interrupt.s \
		keyboard.s keycodes.s acpi.s
	$(AS) -o $@ $<
	../util/checksymbols $@
