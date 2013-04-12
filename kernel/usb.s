##############################################################################
# USB 
.intel_syntax noprefix
##############################################################################

USB_DEBUG = 1


.struct DEV_PCI_STRUCT_SIZE
.align 4
usb_name:	.long 0
.align 4
usb_api:
usb_api_print_status: .long 0 # so that api len is not 0 - for loop.
usb_api_end:
DEV_PCI_USB_STRUCT_SIZE = .
.text32

usb_obj_init:
	ret


############################################################################
# structure for the device object instance:
# append field to nic structure (subclass)
.struct DEV_PCI_USB_STRUCT_SIZE
.align 4
VID_USB_EHCI_STRUCT_SIZE = .

DECLARE_PCI_DRIVER SERIAL_USB_EHCI, usb, 0x15ad, 0x0770, "vmw-ehci", "VMWare EHCI USB Host Controller", usb_vmw_ehci_init
############################################################################
.text32

usb_vmw_ehci_init:
	DEBUG "EHCI Driver"
	ret
