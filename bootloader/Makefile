all: boot.bin

clean:
	[ -f boot.bin ] && /bin/rm boot.bin || true
	[ -f bootloader.o ] && /bin/rm bootloader.o || true

AS = /bin/as -R -n --warn --fatal-warnings

boot.bin: bootloader.o
	@../util/checksymbols $<
	@echo "   OBJ $@"
	@objcopy -O binary $< $@

bootloader.o: bootloader.s sector1.s ../16/print.s
	@echo "   AS $@"
	@$(AS) -o $@ $<
	@../util/checksymbols $@ || (rm $@ && false)
