all: boot.bin pxeboot.bin

clean:
	[ -f boot.bin ] && rm boot.bin || true
	[ -f bootloader.o ] && rm bootloader.o || true
	[ -f pxeboot.bin ] && rm pxeboot.bin || true
	[ -f pxeboot.o ] && rm pxeboot.o || true

AS = as --32 -R -n --warn --fatal-warnings
DEPS = ../16/print.s ../16/gdt.s ../kernel/keycodes.s ../16/pmode.s \
	../16/printregisters.s \
	../16/waitkey.s \
	Makefile


boot.bin: bootloader.o
	@../util/checksymbols $<
	@echo "  OBJ   $@"
	@objcopy -O binary $< $@

pxeboot.bin: pxeboot.o
	@../util/checksymbols $<
	@echo "  OBJ   $@"
	@objcopy -O binary $< $@
	@#objcopy -O binary --change-start 0x7c00 $< $@
	@#objcopy -O binary -j .text $< $@.text
	@#objcopy -O binary -j .data $< $@.data
	@#ld --script bootloader.link $< -o $@.b
	@#cat $@.text $@.data > $@

bootloader.o: bootloader.s sector1.s $(DEPS)
	@echo "  AS    $@"
	@$(AS) -o $@ $<
	@../util/checksymbols $@ || (rm $@ && false)

pxeboot.o: pxeboot.s $(DEPS)
	@echo "  AS    $@"
	@$(AS) -o $@ $<
	@../util/checksymbols $@ || (rm $@ && false)
