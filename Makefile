ALL: os.iso

os.iso: init build/boot.img
	@echo Generating $@
	@cp build/boot.img root/boot/boot.img
	@genisoimage -o os.iso \
	-r -b boot/boot.img \
	root/

	#-J -boot-info-table 
	#-boot-load-size 2884 \
	#-no-emul-boot \
	#-hard-disk-boot 

init:
	mkdir -p build/

clean:
	rm -rf build/ os.iso root/boot/build.img

build/boot.img: build/boot.bin build/write.exe
	build/write.exe -b build/boot.bin -o $@ && chmod 644 $@


#ASSEMBLER=FASM
ASSEMBLER=GAS


build/boot.bin: bootloader.s other-assemblers/bootloader-fasm.asm
ifeq ($(ASSEMBLER),FASM)
	d:/apps/fasm/FASM.EXE other-assemblers/bootloader-fasm.asm $@
	cp other-assemblers/bootloader-fasm.bin $@
else
ifeq ($(ASSEMBLER),GAS)
	/bin/as -o build/bootloader.o bootloader.s
	objcopy -O binary build/bootloader.o $@
endif
endif


build/write.exe: write.cpp
	gcc $< -o $@
