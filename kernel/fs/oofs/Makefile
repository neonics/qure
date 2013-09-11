all: oofs.o export.h

clean:
	rm -f *.o .dep || true

INC = -I ../../

AS = as --32 -march=i486 -n --warn --fatal-warnings --gstabs --MD .dep $(INC)

DEPS = ../fs_oofs.s ../../fs.s ../../oo.s ../../lib/hash.s \
	../../debugger/export.s \
	../../print.s ../../macros.s ../../defines.s extern.h

oofs.o: oofs.s oofs_*.s $(DEPS) Makefile
	@echo "   AS   $@"
	@$(AS) -o $@ $<

export.h: oofs.o Makefile
	@# create file with constants: list absolute symbols.
	@#  (-g: only global/external symbols - speed)
	@echo "   H    $@"
	@nm -f bsd -g --defined-only $< \
	| grep ' A ' \
	| perl -ne 's/(\S+) . (\S+)/\2=0x\1/; print' \
	> $@
