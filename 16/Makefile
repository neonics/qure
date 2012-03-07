all: boot.bin

clean:
	/bin/rm boot.bin sector2.o

AS = /bin/as -R -n --warn --fatal-warnings

boot.bin: sector2.o
	../util/checksymbols $<
	objcopy -O binary $< $@

sector2.o: menu.s print.s \
		floppy.s gfxmode.s keyboard16.s
	$(AS) -o $@ $<
	../util/checksymbols $@
