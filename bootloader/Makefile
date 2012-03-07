all: boot.bin

clean:
	/bin/rm boot.bin bootloader.o

AS = /bin/as -R -n --warn --fatal-warnings

boot.bin: bootloader.o
	../util/checksymbols $<
	objcopy -O binary $< $@

bootloader.o: bootloader.s sector1.s ../16/print.s
	$(AS) -o $@ $<
	../util/checksymbols $@ || (rm $@ && false)
