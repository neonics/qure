all: boot.bin

clean:
	[ -f boot.bin ] && rm boot.bin || true
	[ -f bootloader.o ] && rm bootloader.o || true

AS = as --32 -R -n --warn --fatal-warnings

boot.bin: bootloader.o
	@../util/checksymbols $<
	@echo "  OBJ   $@"
	@objcopy -O binary $< $@

bootloader.o: bootloader.s sector1.s ../16/print.s ../16/gdt.s ../kernel/keycodes.s ../16/pmode.s
	@echo "  AS    $@"
	@$(AS) -o $@ $<
	@../util/checksymbols $@ || (rm $@ && false)
