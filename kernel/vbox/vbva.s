##############################################################################
# Bochs / VirtualBox Video Driver
.intel_syntax noprefix

DECLARE_PCI_DRIVER VID_VGA, vbva, 0x80ee, 0xbeef, "vbva", "VBox Video"

DECLARE_CLASS_BEGIN vbva, vid
DECLARE_CLASS_METHOD dev_api_constructor, vbva_init, OVERRIDE
DECLARE_CLASS_END vbva

.text32
vbva_init:
	I "VirtualBox Video Driver"
	call	newline
	ret
