all: oofs.o export.h

clean:
	rm -f *.o .dep export.h _empty_ _empty_.s || true

INC = -I ../../

IS_ELF = $(shell touch _empty_.s && as -o _empty_ _empty_.s && file _empty_ | grep -c ELF )
AS_DEFS = --defsym ELF=$(IS_ELF)

AS = as --32 -march=i486 -n --warn --fatal-warnings --gstabs --MD .dep $(INC) $(AS_DEFS)

DEPS = ../fs_oofs.s ../../fs.s ../../oo.s ../../lib/hash.s \
	../../debugger/export.s \
	../../print.s ../../macros.s ../../defines.s extern.h


# note: only .s files included in oofs.s will be part of oofs.o
oofs.o: oofs.s oofs_*.s $(DEPS) Makefile
	@echo "  AS    $@"
	@$(AS) -o $@ $<

export.h: oofs.o Makefile
	@# create file with constants: list absolute symbols.
	@#  (-g: only global/external symbols - speed)
	@echo "  H     $@"
	@nm -f bsd -g --defined-only $< \
	| grep ' A ' \
	| perl -ne 's/(\S+) . (\S+)/\2=0x\1/; print' \
	> $@
