.PHONY: all clean init

FONTS =		$(wildcard *.fnt)
FONTS_S =	$(patsubst %.fnt,%.s,$(FONTS))
FONTS_BIN =	$(patsubst %.fnt,%.bin,$(FONTS))

all:	$(FONTS_S) $(FONTS_BIN) ../build/font.exe

%.s: %.fnt ../build/font.exe
	@../build/font.exe $<

init:

clean:
	rm -f $(FONTS_S) $(FONTS_BIN)


../build/font.exe: ../util/font.cpp
	@echo "   GCC $@"
	@gcc $< -o $@
