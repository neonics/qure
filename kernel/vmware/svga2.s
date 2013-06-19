##############################################################################
# VMWare SVGA 2 Video Driver
.intel_syntax noprefix
##############################################################################

VID_DEBUG = 1

VID_STARTUP_CHECK = 1

VMSVGA2_DEBUG = 0

SVGA_FIFO_DEBUG = 0

.text32
############################################################################
# structure for the device object instance:
# append field to nic structure (subclass)
DECLARE_CLASS_BEGIN vmwsvga2, vid
vmwsvga2_capabilities:		.long 0	# SVGA_CAP_* bits
vmwsvga2_fifo_capabilities:	.long 0	# copy of fifo[SVGA_FIFO_CAPABILITIES]
vmwsvga2_device_version:	.byte 0
vmwsvga2_txtmode_bpp:		.byte 0
vmwsvga2_txtmode_w:		.long 0
vmwsvga2_txtmode_h:		.long 0
DECLARE_CLASS_METHOD dev_api_constructor, vmwsvga2_init, OVERRIDE
DECLARE_CLASS_END vmwsvga2

DECLARE_PCI_DRIVER VID_VGA, vmwsvga2, 0x15ad, 0x0405, "vmwsvga2", "VMWare SVGa II"
############################################################################
.text32
DRIVER_VID_VMSVGA2_BEGIN = .


SVGA_MAGIC = 0x00900000

SVGA_MAX_PSEUDOCOLORS_DEPTH = 8
SVGA_MAX_PSEUDOCOLORS = (1<<SVGA_MAX_PSEUDOCOLORS_DEPTH)
SVGA_NUM_PALETTE_REGS = (3*SVGA_MAX_PSEUDOCOLORS)




SVGA_IO_INDEX = 0
SVGA_IO_VALUE = 1
SVGA_IO_BIOS = 2
SVGA_IO_IRQSTATUS = 8
	SVGA_IRQFLAG_ANY_FENCE = 1
	SVGA_IRQFLAG_FIFO_PROGRESS = 2
	SVGA_IRQFLAG_FENCE_FOAL = 4	# probably 'GOAL'


SVGA_REG_ID = 0
	SVGA_ID_2 = 2|(SVGA_MAGIC<<8)
	SVGA_ID_1 = 1|(SVGA_MAGIC<<8)
	SVGA_ID_0 = 0|(SVGA_MAGIC<<8)
	SVGA_ID_INVALID = 0xffffffff
SVGA_REG_ENABLE = 1
SVGA_REG_WIDTH = 2
SVGA_REG_HEIGHT = 3
SVGA_REG_MAX_WIDTH = 4
SVGA_REG_MAX_HEIGHT = 5
SVGA_REG_DEPTH = 6
SVGA_REG_BITS_PER_PIXEL = 7       /* Current bpp in the guest */
SVGA_REG_PSEUDOCOLOR = 8
SVGA_REG_RED_MASK = 9
SVGA_REG_GREEN_MASK = 10
SVGA_REG_BLUE_MASK = 11
SVGA_REG_BYTES_PER_LINE = 12
SVGA_REG_FB_START = 13            /* (Deprecated) */
SVGA_REG_FB_OFFSET = 14
SVGA_REG_VRAM_SIZE = 15
SVGA_REG_FB_SIZE = 16

/* ID 0 implementation only had the above registers then the palette */

SVGA_REG_CAPABILITIES = 17
SVGA_REG_MEM_START = 18           /* (Deprecated) */
SVGA_REG_MEM_SIZE = 19
SVGA_REG_CONFIG_DONE = 20         /* Set when memory area configured */
SVGA_REG_SYNC = 21                /* See "FIFO Synchronization Registers" */
SVGA_REG_BUSY = 22                /* See "FIFO Synchronization Registers" */
SVGA_REG_GUEST_ID = 23            /* Set guest OS identifier */
SVGA_REG_CURSOR_ID = 24           /* (Deprecated) */
SVGA_REG_CURSOR_X = 25            /* (Deprecated) */
SVGA_REG_CURSOR_Y = 26            /* (Deprecated) */
SVGA_REG_CURSOR_ON = 27           /* (Deprecated) */
SVGA_REG_HOST_BITS_PER_PIXEL = 28 /* (Deprecated) */
SVGA_REG_SCRATCH_SIZE = 29        /* Number of scratch registers */
SVGA_REG_MEM_REGS = 30            /* Number of FIFO registers */
SVGA_REG_NUM_DISPLAYS = 31        /* (Deprecated) */
SVGA_REG_PITCHLOCK = 32           /* Fixed pitch for all modes */
SVGA_REG_IRQMASK = 33             /* Interrupt mask */

/* Legacy multi-monitor support */
SVGA_REG_NUM_GUEST_DISPLAYS = 34/* Number of guest displays in X/Y direction */
SVGA_REG_DISPLAY_ID = 35        /* Display ID for the following display attributes */
SVGA_REG_DISPLAY_IS_PRIMARY = 36/* Whether this is a primary display */
SVGA_REG_DISPLAY_POSITION_X = 37/* The display position x */
SVGA_REG_DISPLAY_POSITION_Y = 38/* The display position y */
SVGA_REG_DISPLAY_WIDTH = 39     /* The display's width */
SVGA_REG_DISPLAY_HEIGHT = 40    /* The display's height */

/* See "Guest memory regions" below. */
SVGA_REG_GMR_ID = 41
SVGA_REG_GMR_DESCRIPTOR = 42
SVGA_REG_GMR_MAX_IDS = 43
SVGA_REG_GMR_MAX_DESCRIPTOR_LENGTH = 44

SVGA_REG_TRACES = 45            /* Enable trace-based updates even when FIFO is on */
SVGA_REG_GMRS_MAX_PAGES = 46	# max nr of 4kb pages for all GMRs
SVGA_REG_MEMORY_SIZE = 47	# total dedicated vid mem excl FIFO

SVGA_REG_TOP = 48               /* Must be 1 more than the last register */

SVGA_PALETTE_BASE = 1024        /* Base of SVGA color map */
/* Next 768 (== 256*3) registers exist for colormap */

SVGA_SCRATCH_BASE = SVGA_PALETTE_BASE + SVGA_NUM_PALETTE_REGS
			    /* Base of scratch registers */
/* Next reg[SVGA_REG_SCRATCH_SIZE] registers exist for scratch usage:
First 4 are reserved for VESA BIOS Extension; any remaining are for
the use of the current SVGA driver. */




SVGA_CAP_NONE               = 0x00000000
SVGA_CAP_RECT_COPY          = 0x00000002
SVGA_CAP_CURSOR             = 0x00000020
SVGA_CAP_CURSOR_BYPASS      = 0x00000040   # Legacy (Use Cursor Bypass 3 instd)
SVGA_CAP_CURSOR_BYPASS_2    = 0x00000080   # Legacy (Use Cursor Bypass 3 instd)
SVGA_CAP_8BIT_EMULATION     = 0x00000100
SVGA_CAP_ALPHA_CURSOR       = 0x00000200
SVGA_CAP_3D                 = 0x00004000
SVGA_CAP_EXTENDED_FIFO      = 0x00008000
SVGA_CAP_MULTIMON           = 0x00010000   # Legacy multi-monitor support
SVGA_CAP_PITCHLOCK          = 0x00020000
SVGA_CAP_IRQMASK            = 0x00040000
SVGA_CAP_DISPLAY_TOPOLOGY   = 0x00080000   # Legacy multi-monitor support
SVGA_CAP_GMR                = 0x00100000
SVGA_CAP_TRACES             = 0x00200000


######### 
# FIFO register indices

# Block 1
SVGA_FIFO_MIN		= 4*0
SVGA_FIFO_MAX		= 4*1	# min distance: between min/max: 10k
SVGA_FIFO_NEXT_CMD	= 4*2
SVGA_FIFO_STOP		= 4*3
# Block 2 - extended register: SVGA_CAP_EXTENDED_FIFO
SVGA_FIFO_CAPABILITIES	= 4*4
SVGA_FIFO_FLAGS		= 4*5
SVGA_FIFO_FENCE		= 4*6	# SVGA_FIFO_CAP_FENCE
# Block 3a - optional extended: if SVGA_FIFO_MIN allows room:
SVGA_FIFO_3D_HWVERSION	= 4*7
SVGA_FIFO_PITCHLOCK	= 4*8	# SVGA_FIFO_CAP_PITCHLOCK
SVGA_FIFO_CURSOR_ON	= 4*9	# SVGA_FIFO_CAP_CURSOR_BYPASS_3
SVGA_FIFO_CURSOR_X	= 4*10	# SVGA_FIFO_CAP_CURSOR_BYPASS_3
SVGA_FIFO_CURSOR_Y	= 4*11	# SVGA_FIFO_CAP_CURSOR_BYPASS_3
SVGA_FIFO_CURSOR_COUNT	= 4*12	# SVGA_FIFO_CAP_CURSOR_BYPASS_3
SVGA_FIFO_CURSOR_LAST_UPDATED= 4*13 # SVGA_FIFO_CAP_CURSOR_BYPASS_3
SVGA_FIFO_RESERVED	= 4*14	# SVGA_FIFO_CAP_RESERVE
SVGA_FIFO_CURSOR_SCREEN_ID=4*15	# SVGA_FIFO_CAP_SCREEN_OBJECT
# gap - better not use
SVGA_FIFO_3D_CAPS	= 4*32
SVGA_FIFO_3D_CAPS_LAST	= 4*(32 + 255)
# Block 3b - truly optional extended: valid if FIFO_MIN high enough to leave rum
SVGA_FIFO_GUEST_3D_HWVERSION = 4*(32+255+1)
SVGA_FIFO_FENCE_GOAL	= 4*(32+255+2)
SVGA_FIFO_BUSY		= 4*(32+255+3)
SVGA_FIFO_NUM_REGS	= 32+255+4


# FIFO CAPS
SVGA_FIFO_CAP_FENCE		= 1<<0
SVGA_FIFO_CAP_ACCELFRONT	= 1<<1
SVGA_FIFO_CAP_PITCHLOCK		= 1<<2
SVGA_FIFO_CAP_VIDEO		= 1<<3
SVGA_FIFO_CAP_CURSOR_BYPASS_3	= 1<<4
SVGA_FIFO_CAP_ESCAPE		= 1<<5
SVGA_FIFO_CAP_RESERVE		= 1<<6
SVGA_FIFO_CAP_SCREEN_OBJECT	= 1<<7
SVGA_FIFO_CAP_GMR2		= 1<<8	# te following 4 come from the xf86 code
SVGA_FIFO_CAP_3D_HWVERSION_REVISED= SVGA_FIFO_CAP_GMR2
SVGA_FIFO_CAP_SCREEN_OBJECT_2	= 1<<9
SVGA_FIFO_CAP_DEAD		= 1<<10

# FIFO FLAGS
SVGA_FIFO_FLAG_ACCELFRONT	= 1<<0
SVGA_FIFO_FLAG_RESERVED		= 1<<31


# FIFO Commands
SVGA_CMD_INVALID_CMD		= 0
SVGA_CMD_UPDATE			= 1
SVGA_CMD_RECT_COPY		= 3
SVGA_CMD_DEFINE_CURSOR		= 19
SVGA_CMD_DEFINE_ALPHA_CURSOR	= 22
SVGA_CMD_UPDATE_VERBOSE		= 25
SVGA_CMD_FRONT_ROP_FILL		= 29
SVGA_CMD_FENCE			= 30
SVGA_CMD_ESCAPE			= 33
SVGA_CMD_DEFINE_SCREEN		= 34
SVGA_CMD_DESTROY_SCREEN		= 35
SVGA_CMD_DEFINE_GMRFB		= 36
SVGA_CMD_BLIT_GMRFB_TO_SCREEN	= 37
SVGA_CMD_BLIT_SCREEN_TO_GMRFB	= 38
SVGA_CMD_ANNOTATION_FILL	= 39
SVGA_CMD_ANNOTATION_COPY	= 40
SVGA_CMD_MAX			= 41



# Video Modes:
.data
# unfortunately there is no documentation explaining how to query
# the card for available video modes.
vmwsvga2_vid_modes:
/* 4:3 modes */
.word  320,  240 
.word  400,  300 
.word  512,  384 
.word  640,  480 
.word  800,  600 
.word 1024,  768 	# default
.word 1152,  864
.word 1280,  960 
.word 1376, 1032
.word 1400, 1050 
.word 1600, 1200 
.word 1920, 1440 
.word 2048, 1536 
.word 2360, 1770 # Note: was 2364x1773
.word 2560, 1920 
/* 16:9 modes */ 
.word  854,  480 
.word 1280,  720 
.word 1366,  768 
.word 1600,  900
.word 1920, 1080 
.word 2048, 1152
.word 2560, 1440
/* 16:10 (8:5) modes */ 
.word  320,  200 
.word  640,  400 
.word 1152,  720
.word 1280,  800 
.word 1440,  900 # note: was 1400x900
.word 1680, 1050 
.word 1920, 1200 
.word 2560, 1600 
/* DVD modes */ 
.word  720, 480 # 3:2
.word  720, 576 # 5:4
/* Odd modes */ 
.word  800,  480 # 5:3
.word 1152,  900 # 32x25 (1.28)
.word 1280,  768 # 5:3
.word 1280, 1024 # 5:4
VMWSVGA2_NUM_VIDEO_MODES = (. - vmwsvga2_vid_modes)/4
.text32


.macro VID_WRITE which, val
	.ifnes "\val", "eax"
	mov	eax, SVGA_REG_\which
	out	dx, eax
	mov	eax, \val
	.else
	out	dx, dword ptr SVGA_REG_\which
	.endif
	inc	dx
	out	dx, eax
	dec	dx
.endm

.macro VID_READ which
	mov	eax, SVGA_REG_\which
	out	dx, eax
	inc	dx
	in	eax, dx
	dec	dx
	.if VMSVGA2_DEBUG > 2
		DEBUG "R \which"
		DEBUG_DWORD eax
	.endif
.endm


###############################################################################
.data SECTION_DATA_BSS
vmwsvga_dev: .long 0
.text32

# in: dx = base port
# in: ebx = pci object
vmwsvga2_init:
	push_	ebp edx eax
	push	dword ptr [ebx + dev_io]
	mov	ebp, esp

	mov	[vmwsvga_dev], ebx

	I "VMWare SVGA II Init"
	DEBUG_DWORD ebx

	mov	ecx, [ebx + dev_pci_addr]
	DEBUG_DWORD ecx,"pci_addr"

	xor	al, al
	call	pci_get_bar_addr
	DEBUG_DWORD eax, "BAR0 - ioBase"
	DEBUG_DWORD [ebx+dev_io]

	mov	al, 1
	call	pci_get_bar_addr
	mov	[ebx + vid_fb_addr], eax
	DEBUG_DWORD eax,"BAR1 - framebuffer"

	mov	al, 2
	call	pci_get_bar_addr
	mov	[ebx + vid_fifo_addr], eax
	DEBUG_DWORD eax,"BAR2 -addr fifo"

	call	newline

	mov	dx, [ebx + dev_io]
	mov	ecx, SVGA_ID_2
	.rept 3
	VID_WRITE ID, ecx
	VID_READ ID
	cmp	eax, ecx
	jz	1f
	dec	ecx
	.endr
	printc 12, "SVGA2: Cannot negotiate SVGA device version";
	jmp	9f
1:	print "SVGA device version: "
	movzx	edx, cl
	mov	[ebx + vmwsvga2_device_version], cl
	call	printhex1
	call	newline

	mov	dx, [ebx + dev_io]
	DEBUG_WORD dx
	VID_READ FB_SIZE
	mov	[ebx + vid_fb_size], eax
	DEBUG_DWORD eax,"fb size"
	VID_READ MEM_SIZE
	mov	[ebx + vid_fifo_size], eax
	DEBUG_DWORD eax,"fifo size"
	call	newline

	# enable in paging:
	mov	ecx, [ebx + vid_fb_size]
	mov	eax, [ebx + vid_fb_addr]
	call	paging_idmap_4m

	mov	ecx, [ebx + vid_fifo_size]
	mov	eax, [ebx + vid_fifo_addr]
	call	paging_idmap_4m

	# version 1+ functions:
	cmp	byte ptr [ebx + vmwsvga2_device_version], 1
	jbe	1f
	VID_READ CAPABILITIES
	mov	[ebx + vmwsvga2_capabilities], eax
	print "Capabilities: "

	PRINTFLAG eax, SVGA_CAP_RECT_COPY, "RECT_COPY "
	PRINTFLAG eax, SVGA_CAP_CURSOR, "CURSOR "
	PRINTFLAG eax, SVGA_CAP_CURSOR_BYPASS, "CURSOR_BYPASS "
	PRINTFLAG eax, SVGA_CAP_CURSOR_BYPASS_2, "CURSOR_BYPASS_2 "
	PRINTFLAG eax, SVGA_CAP_8BIT_EMULATION, "8BIT_EMULATION "
	PRINTFLAG eax, SVGA_CAP_ALPHA_CURSOR, "ALPHA_CURSOR "
	PRINTFLAG eax, SVGA_CAP_3D, "3D "
	PRINTFLAG eax, SVGA_CAP_EXTENDED_FIFO, "EXTENDED_FIFO "
	PRINTFLAG eax, SVGA_CAP_MULTIMON, "MULTIMON "
	PRINTFLAG eax, SVGA_CAP_PITCHLOCK, "PITCHLOCK "
	PRINTFLAG eax, SVGA_CAP_IRQMASK, "IRQMASK "
	PRINTFLAG eax, SVGA_CAP_DISPLAY_TOPOLOGY, "DISPLAY_TOPOLOGY "
	PRINTFLAG eax, SVGA_CAP_GMR, "GMR "
	PRINTFLAG eax, SVGA_CAP_TRACES, "TRACES "

1:
	# IRQ setup
	test	eax, SVGA_CAP_IRQMASK
	jz	1f

	DEBUG "Registering ISR"
	VID_WRITE IRQMASK, 0 # mask out all IRQ's
	# clear pending IRQ's
	DEBUG_WORD dx
	add	dx, SVGA_IO_IRQSTATUS
	mov	eax, 0xff
	out	dx, eax
	sub	dx, SVGA_IO_IRQSTATUS
	call	vmwsvga2_hook_isr
1:


9:	call	newline

	# TEST: set video mode.
	# set up the fifo
	push	fs
	mov	eax, SEL_flatDS	# fifo out of range of kernel DS
	mov	fs, eax
		# set vid mode - doesn't have to be in the 'fs' block,
		# but needs to happen before the fifo enable.

		mov	dx, [ebx + dev_io]

		VID_READ WIDTH
		mov	[ebx + vmwsvga2_txtmode_w], eax
		VID_READ HEIGHT
		mov	[ebx + vmwsvga2_txtmode_h], eax
		VID_READ BITS_PER_PIXEL
		mov	[ebx + vmwsvga2_txtmode_bpp], al

		VID_WRITE WIDTH, 1024
		VID_WRITE HEIGHT, 768
		VID_WRITE BITS_PER_PIXEL, 32

		VID_WRITE ENABLE, 1	# even without writing w/h it'll switch mode

		VID_READ BYTES_PER_LINE
		DEBUG_DWORD eax,"pitch"

		call	newline

	mov	edi, [ebx + vid_fifo_addr]
	DEBUG_DWORD edi,"fifo"

	VID_WRITE CONFIG_DONE, 0

		DEBUG_DWORD fs:[edi+SVGA_FIFO_MIN], "FIFO min"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_MAX], "FIFO max"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_NEXT_CMD], "FIFO next"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_STOP], "FIFO stop"
		call	newline

	#GDT_GET_BASE edx, fs
	#sub	edi, edx # its probably a flat hardware address

	mov	eax, SVGA_FIFO_NUM_REGS * 4
	mov	fs:[edi + SVGA_FIFO_MIN], eax
	mov	fs:[edi + SVGA_FIFO_NEXT_CMD], eax
	mov	fs:[edi + SVGA_FIFO_STOP], eax
	mov	eax, [ebx + vid_fifo_size]
	mov	fs:[edi + SVGA_FIFO_MAX], eax

		println "POST FIFO init:"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_MIN], "FIFO min"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_MAX], "FIFO max"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_NEXT_CMD], "FIFO next"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_STOP], "FIFO stop"
		call	newline



	test	dword ptr [ebx + vmwsvga2_capabilities], SVGA_CAP_EXTENDED_FIFO
	jz	1f
	# check: SVGA_FIFO_GUEST_3D_HWVERSION < SVGA_FIFO_MIN - assume ok here.
#	mov	[edi + SVGA_FIFO_GUEST_3D_HWVERSION], SVGA3D_HWVERSION_CURRENT
1:

	# enable FIFO
	DEBUG "enable FIFO"
	mov	dx, [ebx + dev_io]
	DEBUG_WORD dx
	VID_WRITE CONFIG_DONE, 1

	# this value can only be read after fifo enable.
	print "FIFO Capabilities: "
	mov	eax, [ebx + vid_fifo_addr]
	mov	eax, fs:[eax + SVGA_FIFO_CAPABILITIES]
	mov	[ebx + vmwsvga2_fifo_capabilities], eax
	DEBUG_DWORD eax
	PRINTFLAG eax, SVGA_FIFO_CAP_FENCE, "FENCE "
	PRINTFLAG eax, SVGA_FIFO_CAP_ACCELFRONT, "ACCELFRONT "
	PRINTFLAG eax, SVGA_FIFO_CAP_PITCHLOCK, "PITCHLOCK "
	PRINTFLAG eax, SVGA_FIFO_CAP_VIDEO, "VIDEO "
	PRINTFLAG eax, SVGA_FIFO_CAP_CURSOR_BYPASS_3, "CURSOR_BYPASS_3 "
	PRINTFLAG eax, SVGA_FIFO_CAP_ESCAPE, "ESCAPE "
	PRINTFLAG eax, SVGA_FIFO_CAP_RESERVE, "RESERVE "
	PRINTFLAG eax, SVGA_FIFO_CAP_SCREEN_OBJECT, "SCREEN_OBJECT "
	PRINTFLAG eax, SVGA_FIFO_CAP_GMR2, "GMR2 "
	PRINTFLAG eax, SVGA_FIFO_CAP_SCREEN_OBJECT_2, "SCREEN_OBJECT_2 "
	PRINTFLAG eax, SVGA_FIFO_CAP_DEAD, "DEAD "

	call	newline


	# do an IRQ sanity check
	test	dword ptr [ebx + vmwsvga2_capabilities], SVGA_CAP_IRQMASK
	jz	1f
	DEBUG "Test IRQFLag for FENCE"
	VID_WRITE IRQMASK, SVGA_IRQFLAG_ANY_FENCE

	call	svga_fifo_insert_fence
		println "POST FIFO FENCE:"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_MIN], "FIFO min"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_MAX], "FIFO max"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_NEXT_CMD], "FIFO next"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_STOP], "FIFO stop"



	# original behaviour:
	# write to SYNC (which sets BUSY to 1), then poll BUSY, to drain the FIFO.

	# advice: do not write REG_SYNC unless FIFO_BUSY is false.
	VID_WRITE SYNC, 1
	mov	dword ptr fs:[edi + SVGA_FIFO_BUSY], 1	# advised

0:	VID_READ BUSY	# triggers async exec of FIFO commands
	DEBUG_DWORD eax,"BUSY.."
	or	eax, eax
	jnz	0b

	VID_WRITE IRQMASK, 0

	# TODO: check if there was an IRQ.
1:	pop	fs

	call	newline

.if VID_STARTUP_CHECK
	# this will automatically sync/flush on vid mem write,
	# as the FIFO doesn't work as expected yet.
	test	dword ptr [ebx + vmwsvga2_capabilities], SVGA_CAP_TRACES
	jz	1f
jmp	1f
	VID_WRITE TRACES, 1
1:
	push	es
	mov	edi, SEL_flatDS
	mov	es, edi
	mov	edi, [ebx + vid_fb_addr]
mov [vidfbuf], edi
	mov	eax, 0x00ff8822
	mov	ecx, 1024 * 768
	cld
	rep	stosd
	pop	es


mov [vidw], dword ptr 1024
mov [vidh], dword ptr 768
mov [vidbpp], dword ptr 4*8
mov [vidb], dword ptr 4


push	dword ptr [screen_update]

	mov	[curfont], dword ptr offset font_4k_courier #_courier56
	mov	[fontwidth], dword ptr 8
	mov	[fontheight], dword ptr 16
	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_8x16
mov	[screen_update], dword ptr offset gfx_txt_screen_update

	DEBUG_DWORD edi,"FB addr"
	DEBUG_DWORD ecx,"screensize"
	call	newline
	pushad
	call	cmd_colors
	mov ecx, 80
	xor	edx, edx
	0:	call	printdec32
		inc	dl
		cmp	dl, 10
		jb	1f
		xor	edx, edx
	1:	loop	0b
	popad

.if 1
	call	svga_fifo_cmd_update_full
.if 0
	VID_WRITE SYNC, 1
	#mov	dword ptr fs:[edi + SVGA_FIFO_BUSY], 1	# advised
	# causes a hang.
0:	VID_READ BUSY	# triggers async exec of FIFO commands
	DEBUG_DWORD eax,"BUSY"
	or	eax, eax
	jnz	0b
.endif
.endif

.if 0
0:xor eax,eax
call keyboard
	push	edx
	mov dx, ax; call printhex4
	call	printhex4
	pop	edx

	call	svga_fifo_cmd_update_full
cmp ax, K_ENTER
jnz 0b
.endif

pop	dword ptr [screen_update]
	call	newline
.endif

	# disable SVGA, return to VGA. (textmode!)
	VID_WRITE ENABLE, 0
	#VID_WRITE WIDTH, [ebx+vmwsvga2_txtmode_w]
	#VID_WRITE HEIGHT, [ebx+vmwsvga2_txtmode_h]
	#VID_WRITE BITS_PER_PIXEL, [ebx+vmwsvga2_txtmode_bpp]

	clc
	pop	edx
	pop_	eax edx ebp
	ret


vmwsvga2_hook_isr:
	mov	[vmwsvga2_isr_dev], ebx	# XX direct mem offset
	push	ebx
	movzx	ax, byte ptr [ebx + dev_irq]
	mov	[vmwsvga2_isr_irq], al
	mov	ebx, offset vmwsvga2_isr
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

################################################################

################################################################
# Interrupt Service Routine
.data
vmwsvga2_isr_irq: .byte 0
vmwsvga2_isr_dev: .long 0	# direct memory address of device object
.text32
vmwsvga2_isr:
	pushad
	push	ds
	push	es
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	mov	ebx, [vmwsvga2_isr_dev]
	mov	dx, [ebx + dev_io]
	add	dx, SVGA_IO_IRQSTATUS
	in	eax, dx	# read IRQ flags
	or	eax, eax
	jz	9f	# not for us
	out	dx, eax	# (?) mark as handled

	.if 1#VMSVGA2_DEBUG
		printc 0xf5, "VID ISR"
	.endif



	DEBUG_DWORD eax,"IRQ FLAGS"

	.if VMSVGA2_DEBUG
		call	newline
	.endif
########################################################################
9:
.if !IRQ_SHARING
	mov	ebx, [vmwsvga2_isr_dev]
	PIC_SEND_EOI [ebx + dev_irq]
.endif

	pop	es
	pop	ds
	popad	# edx ebx eax
	iret

############################################################################

# in: ebx = device
svga_fifo_insert_fence:
	push_	edx eax fs edi
	mov	edx, SEL_flatDS
	mov	fs, edx

	mov	eax, 8
	call	svga_fifo_reserve$
	DEBUG_DWORD edi,"FIFO RESERVE"
	mov	dword ptr fs:[edi + 0], SVGA_CMD_FENCE
	mov	dword ptr fs:[edi + 4], 1	# fence id; 0 = no fence # TODO: inc fence

	call	svga_fifo_commit$

	pop_	edi fs eax edx
	ret

# FB screen write updates can be automatic using SVGA_REG_TRACES,
# which is enabled by default if fifo is disabled.
#
# in: ebx = svga dev
# in: STACKARGS: x, y, w, h (h pushed first)
# Caller clears stack.
svga_fifo_cmd_update:
	push	ebp
	lea	ebp, [esp + 8]
	push_	edx eax fs edi
	mov	edx, SEL_flatDS
	mov	fs, edx

	mov	eax, 5*4
	call	svga_fifo_reserve$

	push	es
	mov	esi, ebp
	mov	eax, SEL_flatDS
	mov	es, eax
	mov	eax, SVGA_CMD_UPDATE
	stosd	# command
	movsd	# x
	movsd	# y
	movsd	# w
	movsd	# h
	pop	es

	call	svga_fifo_commit$
inc dword ptr fifo_updates$
	pop_	edi fs eax edx
	pop	ebp
	ret

# FB screen write updates can be automatic using SVGA_REG_TRACES,
# which is enabled by default if fifo is disabled.
#
# in: ebx = svga dev
svga_fifo_cmd_update_full:
	push_	edx eax fs edi
	mov	edx, SEL_flatDS
	mov	fs, edx

	mov	eax, 5*4
	call	svga_fifo_reserve$
	mov	dword ptr fs:[edi + 0], SVGA_CMD_UPDATE
	mov	dword ptr fs:[edi + 4], 0	# x
	mov	dword ptr fs:[edi + 8], 0	# y
	mov	dword ptr fs:[edi + 12], 1024	# w
	mov	dword ptr fs:[edi + 16], 768	# h

	call	svga_fifo_commit$
inc dword ptr fifo_updates$
	pop_	edi fs eax edx
	ret



.data SECTION_DATA_BSS
fifo_updates$: .long 0
.text32

# in: fs = SEL_flatDS
# in: ebx = device
# in: eax = size to reserve
# out: edi = reserved address
svga_fifo_reserve$:
	# check: HasFIFOCap(SVGA_FIFO_CAP_RESERVE)
	test	al, 3
	jnz	91f

# Code to check whether and where there is room in the FIFO,
# similar to the NETQUEUE code.
# 
# Pseudo Code:
# 
# if NEXT_CMD >= STOP	// no FIFO data between NEXT and MAX.
#	if NEXT + bytes < MAX	// contiguous fit
#	|| (NEXT + bytes == MAX && STOP > MIN)	// == fits, but if STOP<=MIN,
#						// FIFO would be entirely full.
#		reserveInPlace = true;
#	else if ( (max-NEXT) + (STOP-MIN) <= bytes )
#		// need split but still not enough space:
#		FIFOFull(); # block
#	else
#		// fits but need to split
#		needBounce = true; // assure contiguous buffer
# else			// there is FIFO data between NEXT and MAX.
#	if ( NEXT + bytes < stop )
#		reserveInPlace = true; // enough room between NEXT and STOP.
#	else
#		FIFOFull();
# 
# 
#
#	push_	edx esi eax ecx
#	mov	esi, [ebx + vid_fifo_addr]
#	mov	ecx, fs:[esi + SVGA_FIFO_NEXT_CMD]
#0:	mov	edx, fs:[esi + SVGA_FIFO_STOP]
#
#	cmp	ecx, edx
#	jb	1f
#	# nextCMD >= stop
#	add	eax, edx
#	cmp	eax, fs:[esi + SVGA_FIFO_MAX]
#	jb	2f
#	ja	3f	# no go
#	# equal: it'll fit to the end, but must not fill FIFO entirely;
#	# check if there is still some room at the bottom:
#	cmp	edx, fs:[esi + SVGA_FIFO_MIN]
#	jbe	3f	# no go
#	# there is room
#2:	# fits in place.
#
#
#3:	# no go.
#	
#
#1:
#	pop_	ecx eax esi edx


#	if reserveInPlace
#		if ( reservable || bytes <= 4 )
	mov	edi, [ebx + vid_fifo_addr]
	.if SVGA_FIFO_DEBUG > 1
		DEBUG_DWORD edi,"FIFO addr"
		DEBUG_DWORD eax,"Reservation"
	.endif
	mov	fs:[edi + SVGA_FIFO_RESERVED], eax
	add	edi, fs:[edi + SVGA_FIFO_NEXT_CMD]
	.if SVGA_FIFO_DEBUG > 1
		DEBUG_DWORD edi,"FIFO next"
	.endif
	ret
#		else needbounce=true
#
#	if needbounce
#	return offset bouncebuffer


91:	printc 4, "FIFO command size not % 32"
	int	3
	ret

# in: fs = SEL_flatDS
# in: ebx = device
# the commit size may be smaller than the reserved size.
svga_fifo_commit$:
	push_	esi eax
	mov	esi, [ebx + vid_fifo_addr]
	# next, min, max, reservable
	mov	eax, fs:[esi + SVGA_FIFO_RESERVED]	# off driver uses separate struct
	or	eax, eax
	jz	9f
	add	eax, fs:[esi + SVGA_FIFO_NEXT_CMD]
	cmp	eax, fs:[esi + SVGA_FIFO_MAX]
	jb	1f
	sub	eax, fs:[esi + SVGA_FIFO_MAX]
	add	eax, fs:[esi + SVGA_FIFO_MIN]
1:	mov	fs:[esi + SVGA_FIFO_NEXT_CMD], eax
	# off driver sets reserved to 0 HERE - we did it before.
	mov	fs:[esi + SVGA_FIFO_RESERVED], dword ptr 0

1:	pop_	eax esi
	ret

9:	printc 4, "FIFO commit: no reservation"
	jmp	1b


#############################################################################
.data
gfx_mode$: .byte 0	# = 0 txt mode, 1 = gfx mode
screen_update_old: .long 0
.text32

cmd_gfx:
	xor	byte ptr [gfx_mode$], 1
	jz	init_textmode$

# enter gfx mode:
	mov	ebx, [vmwsvga_dev]

	push	fs
	mov	eax, SEL_flatDS	# fifo out of range of kernel DS
	mov	fs, eax

	mov	dx, [ebx + dev_io]

	VID_WRITE WIDTH, 1600#1024
	VID_WRITE HEIGHT, 900#768
	VID_WRITE BITS_PER_PIXEL, 32

	VID_WRITE ENABLE, 1	# even without writing w/h it'll switch mode

	VID_WRITE CONFIG_DONE, 0
	# init fifo
	mov	edi, [ebx + vid_fifo_addr]

	mov	eax, SVGA_FIFO_NUM_REGS * 4
	mov	fs:[edi + SVGA_FIFO_MIN], eax
	mov	fs:[edi + SVGA_FIFO_NEXT_CMD], eax
	mov	fs:[edi + SVGA_FIFO_STOP], eax
	mov	eax, [ebx + vid_fifo_size]
	mov	fs:[edi + SVGA_FIFO_MAX], eax

		println "POST FIFO init:"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_MIN], "FIFO min"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_MAX], "FIFO max"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_NEXT_CMD], "FIFO next"
		DEBUG_DWORD fs:[edi+SVGA_FIFO_STOP], "FIFO stop"
		call	newline

	# enable FIFO
	mov	dx, [ebx + dev_io]
	VID_WRITE CONFIG_DONE, 1
	VID_WRITE IRQMASK, 0
	pop	fs

	mov	edi, [ebx + vid_fb_addr]
	mov	[vidfbuf], edi

	VID_READ WIDTH
	mov	[vidw], eax #dword ptr 1024
	VID_READ HEIGHT
	mov	[vidh], eax #dword ptr 768
	VID_READ BITS_PER_PIXEL
	mov	[vidbpp], eax#dword ptr 4*8
	shr	eax, 3
	mov	[vidb], eax#dword ptr 4

	mov	eax, [screen_update]
	mov	[screen_update_old], eax

	mov	[curfont], dword ptr offset fonts4k#font_4k_courier #_courier56
	mov	[fontwidth], dword ptr 8
	mov	[fontheight], dword ptr 16
	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_8x16

	mov	[screen_update], dword ptr offset svga_txt_screen_update

	println "entered gfx mode"
	ret


init_textmode$:
	mov	eax, [screen_update_old]
	mov	[screen_update], eax
	# disable SVGA, return to VGA. (textmode!)
	mov	ebx, [vmwsvga_dev]
	mov	dx, [ebx + dev_io]
	VID_WRITE ENABLE, 0
	println	"entered text mode"
	ret

9:	printlnc 4, "usage: gfx"
	printlnc 4, "   toggles between gfx/textmode"
	ret

svga_txt_screen_update:
	push	eax
	mov	eax, cs
	and	al, 3
	pop	eax
	jz	1f
	call	SEL_kernelCall, 0
1:
	push_	eax ds es
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	call	gfx_txt_screen_update

	pushad
	push	dword ptr [screen_update]
	mov	dword ptr [screen_update], offset default_screen_update	# prevent recursion on print

	mov	ebx, [vmwsvga_dev]
	mov	dx, [ebx + dev_io]
	push	dword ptr 25 * 16
	push	dword ptr 80 * 8
	push	dword ptr 0
	push	dword ptr 0
	call	svga_fifo_cmd_update
	add	esp, 16

#	VID_WRITE SYNC, 1
#	VID_READ BUSY

	pop	dword ptr [screen_update]
	popad

	pop_	es ds eax
	ret


cmd_svga:
	push	fs
	mov	eax, SEL_flatDS
	mov	fs, eax
	mov	ebx, [vmwsvga_dev]
	mov	edi, [ebx + vid_fifo_addr]
	DEBUG_DWORD fs:[edi+SVGA_FIFO_MIN], "FIFO min"
	DEBUG_DWORD fs:[edi+SVGA_FIFO_MAX], "FIFO max"
	DEBUG_DWORD fs:[edi+SVGA_FIFO_NEXT_CMD], "FIFO next"
	DEBUG_DWORD fs:[edi+SVGA_FIFO_STOP], "FIFO stop"
	call	newline
	DEBUG_DWORD [fifo_updates$]
	call	newline

	pop	fs
	ret

DRIVER_VID_VMSVGA2_SIZE =  . - DRIVER_VID_VMSVGA2_BEGIN
