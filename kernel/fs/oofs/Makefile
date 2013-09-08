all: oofs.o obj.o

clean:
	rm -f *.o .dep || true

AS = as --32 -march=i486 -n --warn --fatal-warnings --gstabs --MD .dep

DEPS = ../fs_oofs.s ../../fs.s ../../oo.s ../../lib/hash.s \
	../../debugger/export.s \
	../../print.s ../../macros.s ../../defines.s extern.h

%.o: %.s $(DEPS)
	@echo "   AS   $@"
	@$(AS) -o $@ $<

oofs.o: oofs.s oofs_*.s $(DEPS)
	@echo "   AS   $@"
	@$(AS) -o $@ $<
