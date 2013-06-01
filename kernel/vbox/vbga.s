##############################################################################
# VirtualBox Addon Driver
.intel_syntax noprefix

DECLARE_PCI_DRIVER INTPER_OTHER, vbga, 0x80ee, 0xcafe, "vbga", "VBox Guest Addon"

DECLARE_CLASS_BEGIN vbga, dev_pci
DECLARE_CLASS_METHOD dev_api_constructor, vbga_init, OVERRIDE
DECLARE_CLASS_END vbga

.text32
vbga_init:
	I "VirtualBox Guest Driver"
	call	newline
	ret
