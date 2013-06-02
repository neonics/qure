##############################################################################
# USB
.intel_syntax noprefix
##############################################################################

USB_DEBUG = 1

DECLARE_CLASS_BEGIN usb, dev_pci
usb_name:	.long 0
DECLARE_CLASS_END usb
.text32


############################################################################
# structure for the device object instance:
# append field to nic structure (subclass)
DECLARE_CLASS_BEGIN usb_ehci, usb
usb_ehci_cap_regbase:	.long 0
usb_ehci_op_regbase:	.long 0
usb_ehci_nports:	.byte 0

# periodic list (max 4k)
usb_ehci_plist_buf:	.long 0	# mallocced, for freeing
usb_ehci_plist:		.long 0	# 4k hardware aligned ds relative

# async list (size is probably unlimited)
usb_ehci_alist_buf:	.long 0	# mallocced, for freeing
usb_ehci_alist:		.long 0	# 4k hardware aligned ds relative

usb_ehci_dev_companion:	.long 0	# USB 1.1 UHCI or OHCI
DECLARE_CLASS_METHOD dev_api_constructor, usb_vmw_ehci_init, OVERRIDE
DECLARE_CLASS_END usb_ehci

DECLARE_PCI_DRIVER SERIAL_USB_EHCI, usb_ehci, 0x15ad, 0x0770, "vmw-ehci", "VMWare EHCI USB Host Controller"
DECLARE_PCI_DRIVER SERIAL_USB_EHCI, usb_ehci, 0x8086, 0x265c, "intel-ehci", "Intel EHCI USB Host Controller"
############################################################################
.text32

# PCI registers:
USB_EHCI_PCI_CONFIG_SBRN	= 0x60 # serial bus release number: 0x20 = 2.0
USB_EHCI_PCI_CONFIG_FLADJ	= 0x61 # frame length adjustment
	# low 6 bits + 59488 = SOF counter clock periods; default 32

USB_EHCI_PCI_CONFIG_PORTWAKECAP	= 0x62 # opt; port wake capability:
	# bit: indicates if implemented
	# other bits: bitmask for physical port;
	# has no effect - BIOS sets policy, driver implements.

# These are relative to EECP (HCCPARAMS reg)
USB_EHCI_PCI_CONFIG_USBLEGSUP	= 0x00 # extended cap reg for ehci ownership
	# bit 24: OS owned semapahore: set to 0 to request,
	# ownership obtained when reads as 1 and BIOS sem = 0
	# bit 16: BIOS owned semaphore.
	# bits 15:8 next cap pointer (pci config ptr); 0=end
	# bits 7:0 capability id: 01=legacy (requires EECP+4 for status)
USB_EHCI_PCI_CONFIG_USBLEGCTLSTS = 0x04 # leg supp control/status


#############
# USB Host Controller Registers: dev_mmio + ...

# Capability registers:
USB_EHCI_REG_CAP_CAPLENGTH		= 0x00	# size 1
	# +reg base: begin of operational register space
USB_EHCI_REG_CAP_reserved		= 0x01	# size 1
USB_EHCI_REG_CAP_HCIVERSION		= 0x02	# size 2; interface version nr; BCD of EHCI rev supported
USB_EHCI_REG_CAP_HCSPARAMS		= 0x04	# size 4; structural parameters
	# bits 23:20	debug port nr (optional); 0=N/A; < N_PORTS
	# bit 16	port indicator support (status/control reg support controlling port state)
	# bits 15:12	nr of companion controllers (N_CC)
	# bits 11:8	nr of ports per companion controller (N_PCC)
	# bit 7		port routing rules:
	#			0=first N_PCC ports routed to lowest function nr CC, etc
	#			1=explicit port routing per HCSP_PORTROUTE's first N_PORTS elements
	# bit 4		port power control: port power field in stat/ctrl available
	# bits 3:0	N_PORTS: nr of physical ports and port registers in operational register space; 1..15
USB_EHCI_REG_CAP_HCCPARAMS		= 0x08	# size 4; capability parameters
	# bits 15:8	EHCI extended cap ptr (EECP);
	#			0=N/A; PCI config space ptr, 0x40+
	# bits 7:4	isochronous scheduling threshold
	# bit 2		async schedule park feature cap
	# bit 1		progammable frame list flag:
	#			0=use frame list 1024 elements;
	#			1: USBCMD reg Frame List Size configurable.
	# bit 0		64 bit addressing capability:0=32bit;1=data str mem ptr 64 bit

USB_EHCI_REG_CAP_HCSP_PORTROUTE	= 0x0c	# size 8; companion port route description
	# 15 nybbles (60 bits): index refers to physical port,
	# value refers to companion host controller. 0: lowest numbered function controller, etc.


###########
# Operational registers: located after capabilities registers
# (read CAPLENGTH for offset)
USB_EHCI_REG_CMD	= 0x00	# command
	USB_EHCI_CMD_ITC_SHIFT = 16	# interrupt threshold control: 23:16
	USB_EHCI_CMD_ITC_MASK = 0xff
	USB_EHCI_CMD_ITC	= 0xff << 16
	USB_EHCI_CMD_ASPME	= 1 << 11	# async sched park mode enable
	USB_EHCI_CMD_ASPMC	= 3 << 8	# async sched park mode count
	USB_EHCI_CMD_LIGHT_RESET= 1 << 7	# not required;W1,R until 0
	USB_EHCI_CMD_INTR_AAD	= 1 << 6	# intr on async advance doorbell
	USB_EHCI_CMD_ASE	= 1 << 5	# async schedule enable
	USB_EHCI_CMD_PSE	= 1 << 4	# periodic schedule enable
	USB_EHCI_CMD_FLS	= 0b11 << 2	# frame list size: 1024/(1+val) els
						# 3=reserved; (0=1024;1=512;2=256)
						# 1 el = 4 bytes (0:4kb;1:2kb;2:1kb)
	USB_EHCI_CMD_HCRESET	= 1 << 1	# host controller (hardware)reset
	USB_EHCI_CMD_RUNSTOP	= 1 << 0	# 1=run,0=stop; execute schedule.

	# RO = readonly; RW = read/write; RWC = read/write clear: write 1 clears bit
USB_EHCI_REG_STATUS	= 0x04	# status
	USB_EHCI_STATUS_ASS	= 1 << 15	# RO; async schedule status
	USB_EHCI_STATUS_PSS	= 1 << 14	# RO; periodic schedule status
	USB_EHCI_STATUS_RECLAMATION = 1 << 13	# RO; detect empty async schedule
	USB_EHCI_STATUS_HCHALTED= 1 << 12	# RO; RUNSTOP^1
	USB_EHCI_STATUS_INTR_AA	= 1 << 5	# RWC; intr on async advance
	USB_EHCI_STATUS_HSERR	= 1 << 4	# RWC; Host system error (pci)
	USB_EHCI_STATUS_FLR	= 1 << 3	# RWC; frame list rollover
	USB_EHCI_STATUS_PCD	= 1 << 2	# RWC; port change detect
	USB_EHCI_STATUS_ERRINT	= 1 << 1	# RWC; USB error interrupt
	USB_EHCI_STATUS_INT	= 1 << 0	# RWC; usb interrupt: occurs when:
						# completed transaction where IOC=1

						# short packet
	USB_EHCI_STATUS_INT_MASK= 0b111111

USB_EHCI_REG_INTR	= 0x08	# interrupt mask (1=enabled, 0=disabled)
				# (ack by clear corresp. status bit)
	USB_EHCI_INTR_AA	= 1 << 5	# async advance
	USB_EHCI_INTR_HSERR	= 1 << 4	# host system error
	USB_EHCI_INTR_FLR	= 1 << 3	# frame list rollover
	USB_EHCI_INTR_PCD	= 1 << 2	# port change
	USB_EHCI_INTR_ERRINT	= 1 << 1	# usb error
	USB_EHCI_INTR_INT	= 1 << 0	# usb interrupt

USB_EHCI_REG_FRIDX	= 0x0c	# frame index
USB_EHCI_REG_SEGSEL	= 0x10	# 4Gb segment selector
USB_EHCI_REG_PLISTBASE	= 0x14	# periodic frame list base addr
USB_EHCI_REG_ASYNCLISTADDR	= 0x18	# next async list address
# 1x-3f reserved; aux:
USB_EHCI_REG_CONFIGFLAG	= 0x40	# configured flag
USB_EHCI_REG_PORTSC	= 0x44	# N_PORTS port status/control registers


usb_vmw_ehci_init:
	DEBUG "EHCI Driver"

	# read PCI configuration registers specific for USB:

	mov	al, USB_EHCI_PCI_CONFIG_SBRN
	call	dev_pci_read_config

	print "USB "
	movzx	edx, al
	shr	dl, 4
	call	printdec32
	printchar_ '.'
	mov	dl, al
	and	dl, 0xf
	call	printdec32
	call	printspace

	push	fs
	# use flat ds since ds is limited to kernel size to prevent bugs
	mov	eax, SEL_flatDS
	mov	fs, eax

	# pagemap to prevent page faults
	mov	eax, [ebx + dev_mmio]
	mov	ecx, [ebx + dev_mmio_size]
	call	paging_idmap_4m

	DEBUG_DWORD eax,"mmio"
#	GDT_GET_BASE edx, ds
#	sub	eax, edx

	DEBUG_DWORD eax,"mmio dsrel, cap regbase"
	mov	[ebx + usb_ehci_cap_regbase], eax
	mov	esi, eax
	movzx	edx, byte ptr fs:[eax + USB_EHCI_REG_CAP_CAPLENGTH]
	DEBUG_BYTE dl,"cap regs len"
	add	eax, edx
	mov	[ebx + usb_ehci_op_regbase], eax
	DEBUG_DWORD eax, "op regbase"

	call	newline

	mov	eax, fs:[esi + USB_EHCI_REG_CAP_HCSPARAMS]
	DEBUG_DWORD eax,"HCS Params" # 6

	movzx	edx, al
	and	dl, 0b1111
	print	"Ports: "
	call	printdec32
	mov	[ebx + usb_ehci_nports], dl	# convenience copy
	print	" Mapping: "

	test	eax, 1 << 7	# port routing fields bit
	jz	1f
	mov	edx, fs:[esi + USB_EHCI_REG_CAP_HCSP_PORTROUTE]
	call	printhex8
	mov	edx, fs:[esi + USB_EHCI_REG_CAP_HCSP_PORTROUTE + 4]
	# print 24 bits, 7 nybbles:
	call	printhex4
	shr	edx, 16
	call	printhex2
	shr	edx, 8
	call	printhex1

	jmp	2f
1:	print	"linear"
2:

	# bits 3:0	N_PORTS: nr of physical ports and port registers in operational register space; 1..15

	mov	eax, fs:[esi + USB_EHCI_REG_CAP_HCCPARAMS]
	DEBUG_DWORD eax,"HCC Params" # 2
	# bits 15:8	EHCI extended cap ptr (EECP);
	#			0=N/A; PCI config space ptr, 0x40+
	print	"EECP: "
	or	ah, ah
	jnz	1f
	print	"N/A"
	jmp	2f
1:	mov	dl, ah
	call	printhex2
2:	call	newline

	# operational registers:

	mov	esi, [ebx + usb_ehci_op_regbase]

	DEBUG_DWORD fs:[esi + USB_EHCI_REG_CMD],"CMD"
	DEBUG_DWORD fs:[esi + USB_EHCI_REG_STATUS],"STATUS"
	DEBUG_DWORD fs:[esi + USB_EHCI_REG_INTR],"INTR"
	DEBUG_DWORD fs:[esi + USB_EHCI_REG_FRIDX],"FR IDX"
	DEBUG_DWORD fs:[esi + USB_EHCI_REG_SEGSEL],"SEG SEL"
	DEBUG_DWORD fs:[esi + USB_EHCI_REG_PLISTBASE],"P LISTBASE"
	DEBUG_DWORD fs:[esi + USB_EHCI_REG_ASYNCLISTADDR],"ASYNC LISTADDR"
	# aux
	DEBUG_DWORD fs:[esi + USB_EHCI_REG_CONFIGFLAG],"CFGFLAG"

	call	newline

	call	usb_ehci_print_ports
	call	newline


	# Initialisation

	call	usb_ehci_hook_isr

	# if 64 bit addressing: write SEGSEL for 63:32 bits of addr

	# enable interrupts
	mov	dword ptr fs:[esi + USB_EHCI_REG_INTR], 0b111111 # all 6

	# setup periodic list
	# must be 4k aligned.
USE_MALLOC_ALIGNED = 1

.if USE_MALLOC_ALIGNED
	mov	eax, 4096
	mov	edx, 4096
	call	mallocz_aligned	# BUG
.else
	mov	eax, 4096 * 2
	call	mallocz
.endif
	jc	9f
	mov	[ebx + usb_ehci_plist_buf], eax	# for mfree
	GDT_GET_BASE edx, ds
	sub	eax, edx
.if USE_MALLOC_ALIGNED
.else
	add	eax, 4096
	and	eax, ~4095
.endif
	mov	dword ptr fs:[esi + USB_EHCI_REG_PLISTBASE], eax
	mov	[ebx + usb_ehci_plist], eax



0:	pop	fs
	ret
9:	printlnc 4, "usb echi: cannot allocate frame list"
	jmp	0b

# in: ebx = device
usb_ehci_print_ports:
	push_	esi eax ecx edx fs
	mov	eax, SEL_flatDS
	mov	fs, eax
	mov	esi, [ebx + usb_ehci_op_regbase]
	xor	eax, eax
	movzx	ecx, byte ptr [ebx + usb_ehci_nports]
0:	print	"Port "
	movzx	edx, byte ptr [ebx + usb_ehci_nports]
	sub	edx, ecx
	call	printdec32
	call	printspace
	mov	edx, fs:[esi + USB_EHCI_REG_PORTSC + eax]
	mov	fs:[esi + USB_EHCI_REG_PORTSC + eax], edx # RWC clear bits
	call	printhex8
	call	printspace
	PRINTFLAG edx, 1<<22,"WAKE_OVERCURRENT "	# WKOC_E
	PRINTFLAG edx, 1<<21,"WAKE_DISCONNECT "	# WKDSCNNT_E
	PRINTFLAG edx, 1<<20,"WAKE_CONNECT "	# WKCNNT_E
	# 19:16: port test control
	# 15:14: port indicator control (led) 0=off;1=amber;2=green;3=undef
	PRINTFLAG edx, 1<<13,"PORT_OWN_EHCI ","PORT_OWN_COMPANION "
	PRINTFLAG edx, 1<<12,"PORT_POWER "# HCSPARAMS.PPC ? 1=no control,pwr up : pwr
	# 11:10: line status: (only meaningful if PORT_POWER = 1
	# 0b00=SE0 (not low speed, perform EHCI reset)
	# 0b10=J-state (not lowspeed, perform EHCI reset)
	# 0b01=K-state (low speed, release ownership)
	# 0b11=undefined

	# RW, control:
	PRINTFLAG edx, 1 << 8, "PORT_RESET "
	PRINTFLAG edx, 1 << 7, "PORT_SUSPEND "
		#port enable<<1|suspend:
		# 0?	disable
		# 10	enable
		# 11	suspend
	PRINTFLAG edx, 1 << 6, "PORT_FORCE_RESUME " # 0=no resume(K state)

	PRINTFLAG edx, 1 << 5, "PORT_OVERCURRENT_CHANGE "	# RWC
	PRINTFLAG edx, 1 << 4, "PORT_OVERCURRENT_ACTIVE "	# RO
	PRINTFLAG edx, 1 << 3, "PORT_ENABLED_CHANGE "		# RWC
	PRINTFLAG edx, 1 << 2, "PORT_ENABLED "			# RW
	PRINTFLAG edx, 1 << 1, "PORT_CONNECTED_CHANGE "		# RWC
	PRINTFLAG edx, 1 << 0, "PORT_CONNECTED "		# RWC


	call	newline
	add	eax, 4
	#loop	0b
	dec	ecx
	jnz	0b

	pop_	fs eax ecx edx esi
	ret



.data
usb_ehci_isr_dev:	.long 0
usb_ehci_isr_irq:	.byte 0
.text32
usb_ehci_hook_isr:
	mov	[usb_ehci_isr_dev], ebx	# XX direct mem offset
	push	ebx
	movzx	ax, byte ptr [ebx + dev_irq]
	mov	[usb_ehci_isr_irq], al
	mov	ebx, offset usb_ehci_isr
	add	ebx, [realsegflat]
	mov	cx, cs
.if IRQ_SHARING
	call	add_irq_handler
.else
	add	ax, IRQ_BASE
	call	hook_isr
.endif
	pop	ebx
	mov	al, [ebx + dev_irq]
	call	pic_enable_irq_line32
	ret

usb_ehci_isr:
	pushad
	push_	ds es fs
	mov	eax, SEL_compatDS
	mov	es, eax
	mov	ds, eax
	mov	eax, SEL_flatDS
	mov	fs, eax


	mov	ebx, [usb_ehci_isr_dev]
	mov	esi, [ebx + usb_ehci_op_regbase]

	mov	eax, fs:[esi + USB_EHCI_REG_STATUS]
	mov	edx, eax
	and	edx, USB_EHCI_STATUS_INT_MASK
	jz	9f	# shared irq - not for us

	printc 0xf5, "USB ISR"

	mov	fs:[esi + USB_EHCI_REG_STATUS], eax	# clear bits
	DEBUG "EHCI status: "
	DEBUG_DWORD eax
	PRINTFLAG eax, USB_EHCI_STATUS_INTR_AA, "INTR_AA"
	PRINTFLAG eax, USB_EHCI_STATUS_HSERR, "HSERR"
	PRINTFLAG eax, USB_EHCI_STATUS_FLR, "FLR"
	PRINTFLAG eax, USB_EHCI_STATUS_PCD, "PCD"
	PRINTFLAG eax, USB_EHCI_STATUS_ERRINT, "ERRINT"
	PRINTFLAG eax, USB_EHCI_STATUS_INT, "INT"
	call	newline
	call	usb_ehci_print_ports
.if !IRQ_SHARING
	PIC_SEND_EOI [ebx + dev_irq]
.endif

9:	pop_	fs es ds
	popad
	iret
