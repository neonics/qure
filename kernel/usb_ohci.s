###############################################################################
# USB Open Host Specification Interface
.intel_syntax noprefix

#############################################
# Registers, in four partitions:
#
# Control and Status
OHCI_REG_REVISION		= 0x00
OHCI_REG_CONTROL		= 0x04
OHCI_REG_CMD_STATUS		= 0x08
OHCI_REG_INT_STATUS		= 0x0c
OHCI_REG_INT_ENABLE		= 0x10
OHCI_REG_INT_DISABLE		= 0x14
# Memory Pointer
OHCI_REG_HCCA			= 0x18
OHCI_REG_PERIOD_CURRENT_ED	= 0x1c	# ED=Endpoint Descriptor
OHCI_REG_CONTROL_HEAD_ED	= 0x20
OHCI_REG_CONTROL_CURRENT_ED	= 0x24
OHCI_REG_BULK_HEAD_ED		= 0x28
OHCI_REG_BULK_CURRENT_ED	= 0x2c
OHCI_REG_DONE_HEAD		= 0x30
# Frame Counter
OHCI_REG_FM_INTERVAL		= 0x34
OHCI_REG_FM_REMAINING		= 0x38
OHCI_REG_FM_NUMBER		= 0x3c
OHCI_REG_PERIODIC_START		= 0x40
OHCI_REG_LS_THRESHOLD		= 0x44
# Root Hub
OHCI_REG_RH_DESCRIPTOR_A	= 0x48
OHCI_REG_RH_DESCRIPTOR_B	= 0x4c
OHCI_REG_RH_STATUS		= 0x50
OHCI_REG_RH_PORT_STATUS		= 0x54	# first port; rest follows

############################################################
.text32
DECLARE_CLASS_BEGIN usb_ohci, usb
DECLARE_CLASS_METHOD dev_api_constructor, usb_ohci_init, OVERRIDE
DECLARE_CLASS_END usb_ohci

DECLARE_PCI_DRIVER SERIAL_USB_OHCI, usb_ohci, 0x106b, 0x003f, "appleusb", "Apple KeyLargo/Intrepic USB (OHCI)"

.text32
usb_ohci_init:
	I "USB OHCI Driver"
	call	newline
	push	fs
	mov	eax, SEL_flatDS
	mov	fs, eax

	mov	eax, [ebx + dev_mmio]
	mov	ecx, [ebx + dev_mmio_size]
	call	paging_idmap_4m # actually 4k

	printc 8, "Revision "
	mov	eax, fs:[esi + OHCI_REG_REVISION]
	movzx	edx, al
	call	printdec32
	call	printspace

	printc 8, "Control "
	mov	eax, fs:[esi + OHCI_REG_CONTROL]
	PRINTFLAG eax, 1<<10, "RWE "	# remote wakeup enable
	PRINTFLAG eax, 1<< 9, "RWC "	# remote wakeup connected (supported)
	PRINTFLAG eax, 1<< 8, "IR "	# interupt routing 1=SMI
	PRINTBITSb al, 6, 2, "HCFS "	# host controller functional state
	call	printspace
	PRINTFLAG eax, 1<< 5, "BLE "	# bulk list enable
	PRINTFLAG eax, 1<< 4, "CLE "	# crontrol list enable
	PRINTFLAG eax, 1<< 3, "IE "	# isochronous enable
	PRINTFLAG eax, 1<< 2, "PLE "	# periodic list enable
	PRINTBITSb al, 0, 2, "CBSR "	# control bulk service ratio: (1..4):1

	printc 8, " CommandStatus "
	mov	eax, fs:[esi+OHCI_REG_CMD_STATUS]
	mov	edx, eax
	call	printhex8
	call	printspace
	PRINTBITSd eax, 16,2, "SOC "	# R   RW scheduling overrun count
	call	printspace
	PRINTFLAG al, 3, "OCR "		# RW  RW ownership change request
	PRINTFLAG al, 2, "BLF "		# RW  RW bulk list filled
	PRINTFLAG al, 1, "CLF "		# RW  RW control list filled
	PRINTFLAG al, 0, "HCR "		# RW  RW host controller reset

	call	newline

	printc 8, "Interrupt Status "
	mov	eax, fs:[esi+OHCI_REG_INT_STATUS]
	call	usb_ohci_print_int_flags$	# bit 31 always 0
	# for enable/disable, writing 0 is ignored; writing 1 to the reg
	# will enable or disable it, depending on which reg is written.
	printc 8, "Enable "
	mov	eax, fs:[esi+OHCI_REG_INT_ENABLE]
	call	usb_ohci_print_int_flags$	# bit 31 always 0
	printc 8, "Disable "
	mov	eax, fs:[esi+OHCI_REG_INT_DISABLE]
	call	usb_ohci_print_int_flags$
	call	newline

	### Memory Pointer Partition

	.macro _PH8 label, reg
		printc 8, "\label "
		mov	edx, fs:[esi + OHCI_REG_\reg]
		call	printhex8
		call	printspace
	.endm

	_PH8 "HCCA", HCCA # Host Controller Communication Area physical address
	# HCCA: writing all 1's, then read: low 8 or more bits will be 0
	# indicating alignment - minimum 256 bytes.

	_PH8 "PCED", PERIOD_CURRENT_ED
	_PH8 "CHED", CONTROL_HEAD_ED
	_PH8 "CCED", CONTROL_CURRENT_ED
	_PH8 "BHED", BULK_HEAD_ED
	_PH8 "BCED", BULK_CURRENT_ED
	_PH8 "DH", DONE_HEAD
	call	newline

	# Frame Counter Partition
	printc 8, "Frame Counter Interval "
	mov	eax, fs:[esi+OHCI_REG_FM_INTERVAL]
	PRINTFLAG eax, 31, "FIT "	# frame interval toggle
	PRINTBITSd eax, 16, 15, "FSMPS "# FS largest data packet
	PRINTBITSw ax, 0, 14, "FI "	# frame interval

	printc 8, " Remaining "
	mov	eax, fs:[esi+OHCI_REG_FM_REMAINING]
	PRINTFLAG eax, 31, "FRT "	# frame remaining toggle
	PRINTBITSw ax, 0, 14, "FR "	# frame remaining

	DEBUG_WORD fs:[esi+OHCI_REG_FM_NUMBER], "FM NUMBER" # frame nr
	DEBUG_WORD fs:[esi+OHCI_REG_PERIODIC_START], "PERIODIC START" # 14 bits
	PRINTBITSw fs:[esi+OHCI_REG_LS_THRESHOLD], 0, 11, "LS THRESHOLD "
	call	newline

	# Root Hub Partition
	printc 8, "RootHub Desc A "
	mov	eax, fs:[esi+OHCI_REG_RH_DESCRIPTOR_A]
	DEBUG_DWORD eax
	PRINTBITSd eax, 24, 8, "POTPGT="# poweron to powergood time(2ms *val)
	call	printspace
	PRINTFLAG eax, 12, "NOCP "	# no overcurrent protection
	PRINTFLAG eax, 11, "OCPM "	# overcurrent protection mode (1=indiv)
	PRINTFLAG eax, 10, "DT "	# device type (MUST 0=no compound)
	PRINTFLAG eax,  9, "NPS "	# no power switching(1=always on)
	PRINTFLAG eax,  8, "PSM "	# power switching mode (0=all,1=indiv)
	PRINTBITSb al, 0, 8, "NDP "	# number downstream ports: 1..15

	printc 8, " Desc B "
	mov	eax, fs:[esi+OHCI_REG_RH_DESCRIPTOR_B]
	DEBUG_DWORD eax
	# each bit indicates a root hub port.
	PRINTBITSd eax, 0,16, "DH " # device removable
	PRINTBITSd eax, 16, 16, " PPCM " # port poweron control mask

	printc 8, "RH Status "
	mov	eax, fs:[esi+OHCI_REG_RH_STATUS]
	PRINTFLAG eax, 31, "CRWE "	# clear remote wakeup enable
	PRINTFLAG eax, 17, "OCIC "	# overcurrent indicator change
	PRINTFLAG eax, 16, "LPSC "	# R=localpower status change;W=setglobal
	PRINTFLAG eax, 15, "DRWE "	# R=device remote wakeup enab;W1=disable
	PRINTFLAG eax,  1, "OCI "	# overcurrent indicator
	PRINTFLAG eax,  0, "LPS "	# R:local power status W:clearglobalpwr

	call	newline

	# print port statuses
	# lower word = port status
	# upper word = status change bits
	movzx	ecx, byte ptr fs:[esi + OHCI_REG_RH_DESCRIPTOR_A] # NDP
	lea	edi, [esi + OHCI_REG_RH_PORT_STATUS]
	jecxz	1f
	xor	edx, edx
0:	printc 8, "  Port "
	call	printdec32
	inc	edx
	call	printspace
	mov	eax, fs:[edi]
	push edx; call printhex8; pop edx;
	add	edi, 4
	call	newline
	loop	0b
1:	# no ports

	.purgem _PH8

	call more

	pop	fs
	ret

usb_ohci_print_int_flags$:
	mov	edx, eax
	call	printhex8
	call	printspace
	PRINTFLAG eax, 31, "MIE "	# master interrupt enable
	PRINTFLAG eax, 30, "OC "	# ownership change
	PRINTFLAG eax,  6, "RHSC "	# root hub status change
	PRINTFLAG eax,  5, "FNO "	# frame number overflow
	PRINTFLAG eax,  4, "UE "	# unrecoverable error
	PRINTFLAG eax,  3, "RD "	# resume detected
	PRINTFLAG eax,  2, "SF "	# start of frame
	PRINTFLAG eax,  1, "WDH "	# Writeback Done Head
	PRINTFLAG eax,  0, "SO "	# Scheduling Overrun
	ret


