##############################################################################
# VMWare SVGA 2 Video Driver
.intel_syntax noprefix
##############################################################################

VID_DEBUG = 0

VID_STARTUP_CHECK = 0	# 1=default; 2=keypress; 3=FPS test

VMSVGA2_DEBUG = 0

SVGA_FIFO_DEBUG = 0

# for testing:
SCREEN_WIDTH = 1024
SCREEN_HEIGHT = 768

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
DECLARE_CLASS_METHOD dev_api_isr,	  vmwsvga2_isr,  OVERRIDE
DECLARE_CLASS_METHOD vid_api_gfx_mode, vmwsvga2_gfx_mode, OVERRIDE
DECLARE_CLASS_METHOD vid_api_txt_mode, vmwsvga2_txt_mode, OVERRIDE
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
	call	newline

	xor	al, al
	call	dev_pci_get_bar_addr		# BAR 0 - dev_io

	mov	al, 1
	call	dev_pci_get_bar_addr
	mov	[ebx + vid_fb_addr], eax	# BAR 1 

	mov	al, 2
	call	dev_pci_get_bar_addr
	mov	[ebx + vid_fifo_addr], eax	# BAR 2


	# determine device version
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
9:

	mov	dx, [ebx + dev_io]
	print " IO: "
	call	printhex4
	call	newline

	VID_READ FB_SIZE
	mov	[ebx + vid_fb_size], eax

		print "Framebuffer size: "
		mov	edx, eax
		call	printhex8
		call	printspace
		xor	edx, edx
		call	print_size
		mov	edx, eax
		print " ("
		mov	edx, [ebx + vid_fb_addr]
		call	printhex8
		add	edx, eax
		printchar_ '-'
		call	printhex8
		println ")"

	mov	dx, [ebx + dev_io]
	VID_READ MEM_SIZE
	mov	[ebx + vid_fifo_size], eax

		print "FIFO size: "
		mov	edx, eax
		call	printhex8
		call	printspace
		xor	edx, edx
		call	print_size
		mov	edx, eax
		print " ("
		mov	edx, [ebx + vid_fifo_addr]
		call	printhex8
		add	edx, eax
		printchar '-'
		call	printhex8
		println ")"


	mov	esi, [page_directory_phys]
	mov	eax, [ebx + vid_fb_addr]
	mov	ecx, [ebx + vid_fb_size]
	call	paging_idmap_memrange

	mov	eax, [ebx + vid_fifo_addr]
	mov	ecx, [ebx + vid_fifo_size]
	call	paging_idmap_memrange

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

	VID_WRITE IRQMASK, 0 # mask out all IRQ's
	# clear pending IRQ's
	add	dx, SVGA_IO_IRQSTATUS
	mov	eax, 0xff
	out	dx, eax
	sub	dx, SVGA_IO_IRQSTATUS
	# hook ISR to IRQ and enable PIC IRQ line
	call	dev_add_irq_handler
1:

9:	call	newline

.if VID_STARTUP_CHECK
	call	vmwsvga2_startup_check
.endif

	clc
	pop	edx
	pop_	eax edx ebp
	ret

########################################################
# Video Mode

# in: eax = vid
vmwsvga2_txt_mode:
	push	edx
	mov	dx, [eax + dev_io]
	VID_WRITE ENABLE, 0
	pop	edx
	ret

# in: eax = vid
vmwsvga2_gfx_mode:
	push_	eax ebx edx
	mov	ebx, eax

	mov	dx, [ebx + dev_io]
	VID_WRITE WIDTH, SCREEN_WIDTH
	VID_WRITE HEIGHT, SCREEN_HEIGHT
	VID_WRITE BITS_PER_PIXEL, 32
	VID_WRITE ENABLE, 1	# even without writing w/h it'll switch mode

	VID_READ BITS_PER_PIXEL
	push	eax
	mov	[vidbpp], eax
	shr	eax, 3
	mov	[vidb], eax
	VID_READ HEIGHT
	mov	[vidh], eax
	push	eax
	VID_READ WIDTH
	mov	[vidh], eax
	push	eax
	call	gfx_set_geometry

	printc 10, "VideoMode: "
	pushd	[vidw]
	call	_s_printdec32
	printchar 'x'
	pushd	[vidh]
	call	_s_printdec32
	printchar 'x'
	pushd	[vidbpp]
	call	_s_printdec32
	call	printspace
	pushd	[vidb]
	call	_s_printdec32
	print " bytes/pixel "
	pushd	[vidsize]
	call	_s_printdec32
	print " pixels "
	mov	eax, [vidsize]
	movzx	edx, byte ptr [vidb]
	imul	edx
	xor	edx, edx
	call	print_size
	call	newline

	mov	edx, [ebx + dev_io]


	# init fifo
	push	fs
	VID_WRITE CONFIG_DONE, 0	# disable fifo

	mov	edx, SEL_flatDS	# fifo out of range of kernel DS
	mov	fs, edx

	mov	edx, [ebx + vid_fifo_addr]

	mov	eax, SVGA_FIFO_NUM_REGS * 4
	mov	fs:[edx + SVGA_FIFO_MIN], eax
	mov	fs:[edx + SVGA_FIFO_NEXT_CMD], eax
	mov	fs:[edx + SVGA_FIFO_STOP], eax
	mov	eax, [ebx + vid_fifo_size]
	mov	fs:[edx + SVGA_FIFO_MAX], eax

	test	dword ptr [ebx + vmwsvga2_capabilities], SVGA_CAP_EXTENDED_FIFO
	jz	1f
	# check: SVGA_FIFO_GUEST_3D_HWVERSION < SVGA_FIFO_MIN - assume ok here.
#	mov	[edi + SVGA_FIFO_GUEST_3D_HWVERSION], SVGA3D_HWVERSION_CURRENT
1:

	.if VID_DEBUG
		print "POST FIFO init:"
		call	svga_fifo_print$
	.endif

	# enable FIFO
	mov	dx, [ebx + dev_io]
	VID_WRITE CONFIG_DONE, 1
	VID_WRITE IRQMASK, 0
	pop	fs


#	# this will automatically sync/flush on vid mem write.
#	test	dword ptr [ebx + vmwsvga2_capabilities], SVGA_CAP_TRACES
#	jz	1f
#jmp	1f
#	VID_WRITE TRACES, 1
#1:
	VID_WRITE TRACES, 0	# no speed increase; FIFO works.

	mov	eax, [ebx + vid_fb_addr]
	mov	[vidfbuf], eax
	pop_	edx ebx eax
	ret

##########################################################
# Video Startup Checks
#
.if VID_STARTUP_CHECK
vmwsvga2_startup_check:
mov ebx, [vmwsvga_dev]
	# read textmode resolution
	mov	dx, [ebx + dev_io]
	VID_READ WIDTH
	mov	[ebx + vmwsvga2_txtmode_w], eax
	VID_READ HEIGHT
	mov	[ebx + vmwsvga2_txtmode_h], eax
	VID_READ BITS_PER_PIXEL
	mov	[ebx + vmwsvga2_txtmode_bpp], al
	.if VID_DEBUG
		DEBUG "textmode:"
		DEBUG_DWORD [ebx + vmwsvga2_txtmode_w], "w"
		DEBUG_DWORD [ebx + vmwsvga2_txtmode_h], "h"
		DEBUG_DWORD [ebx + vmwsvga2_txtmode_bpp], "bpp"
	.endif


	# enter graphics mode
	mov	eax, ebx
	INVOKEVIRTUAL vid gfx_mode

	.if VID_DEBUG
	call	svga_fifo_print_capabilities$
	.endif
	call	svga_verify_fifo_irq$


	# Clear screen

	mov	eax, 0x00ff8822
	call	gfx_cls


	# Test console printing

push	dword ptr [screen_update]

	mov	[curfont], dword ptr offset fonts4k #_courier56
	mov	[fontwidth], dword ptr 8
	mov	[fontheight], dword ptr 16
	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_8x16
mov	[screen_update], dword ptr offset gfx_txt_screen_update


	######################
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

	call	svga_fifo_cmd_update_full

	######################


	.if VID_STARTUP_CHECK > 2
	call	vmwsvga_test_fps
	.else
	.if VID_STARTUP_CHECK > 1
	call	vmwsvga_test_font_blit

	printlnc 0xb0, "press a key to continue"
	call	svga_fifo_cmd_update_full
	xor	eax, eax
	call	keyboard
	.endif
	.endif

pop	dword ptr [screen_update]
	call	newline

	# disable SVGA, return to VGA. (textmode!)
	mov	eax, ebx
	INVOKEVIRTUAL vid txt_mode
	ret


###########################################################################
.if VID_STARTUP_CHECK > 2
.data SECTION_DATA_BSS
vidtst_clock: .long 0
vidtst_frames: .long 0
.text32
vmwsvga_test_fps:
	pushad

	mov	eax, [clock]
	mov	[vidtst_clock], eax
0:
	mov	ah, 1#KB_PEEK
	call	keyboard
	jz	1f
	xor	ah, ah
	call	keyboard

	cmp	ax, K_ENTER
	jz	0f

	push	eax
	call	_s_printhex8
	call	printspace

1:	call	fillscreen$

	mov	edx, [vidtst_frames]
	call	printhex8
	call	printspace
	mov	eax, edx	# frames (since start)

	mov	edx, [clock]
	sub	edx, [vidtst_clock]
	call	printhex8
	call	printspace
.if 1
	mov	ecx, edx	# clocks (since start)

	mov	esi, eax	# frames (backup
	inc	esi	# prevent / 0

	# FPS: frames / seconds

	# 32:32 period (ms)
	mov	edx, [pit_timer_period]
	mov	eax, [pit_timer_period+4]
	shrd	eax, edx, 8
	shr	edx, 8
	# mul with clocks
	imul	ecx

	# frames / time
	# trunc to milliseconds:
	shrd	eax, edx, 24	# eax now milliseconds, edx=0 (presumably)
	mov	ecx, eax	# time
	xor	edx, edx
	mov	eax, esi	# frames
	mov	esi, 1000
	imul	esi	# 1000 * frames: corrects ms
	cmp ecx, 100
	jb 1f
	div	ecx		# frames / time

	mov	edx, eax
	call	printdec32	# fps
1:
	# refresh measurement
	cmpd	[vidtst_frames], 1000
	jb	1f
	mov	[vidtst_frames], dword ptr 0
	mov	eax, [clock]
	mov	[vidtst_clock], eax
1:
.endif

	call	newline

	call	svga_fifo_cmd_update_full
	incd	[vidtst_frames]
	jmp	0b

0:	popad
	ret

##################################################

.endif	# VID_STARTUP_CHECK > 2
.if VID_STARTUP_CHECK > 1
.data SECTION_DATA_BSS
fillscreen_color: .long 0x12345678
.text32
fillscreen$:
	push	eax
	add	eax, [fillscreen_color]
	rol	eax, 7
	xor	[fillscreen_color], eax
	call	gfx_cls
	pop	eax
	ret


vmwsvga_test_font_blit:
	call	svga_font_init
#xor eax,eax; call keyboard
	mov	eax, 0
	call	svga_screen_define

	mov	eax, 0x00ff0022
	call	gfx_cls
	print	"Screen defined - press key"
	call	svga_fifo_cmd_update_full
	xor	eax,eax; call keyboard
	mov	eax, 0
	call	svga_screen_destroy

	# nothing renders after this point....
	mov	eax, 0x002200ff
	call	gfx_cls
	call	svga_fifo_cmd_update_full

	push fs
	mov edx,SEL_flatDS
	mov fs,edx
	mov edx,[ebx+dev_io]
	mov edi,[ebx+vid_fifo_addr]
	call svga_fifo_sync$
	pop fs


	call	svga_font_deinit
	ret
.endif
.endif	# VID_STARTUP_CHECK


#############################################################################


.if VID_DEBUG
svga_fifo_print_capabilities$:
	push	fs
	mov	eax, SEL_flatDS	# fifo out of range of kernel DS
	mov	fs, eax
	mov	eax, [ebx + vid_fifo_addr]

	# this value can only be read after fifo enable.
	print "FIFO Capabilities: "
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
	pop	fs
	ret
.endif


# do an IRQ sanity check
#
# in: fs = flat segment
# in: ebx = video device
# destroys: eax ecx edi
# PRECONDITION: FIFO enabled (VID_WRITE CONFIG_DONE, 1)
svga_verify_fifo_irq$:

######
	push	fs
	mov	eax, SEL_flatDS	# fifo out of range of kernel DS
	mov	fs, eax

	print "Verify FIFO IRQ: "
	test	dword ptr [ebx + vmwsvga2_capabilities], SVGA_CAP_IRQMASK
	jz	91f

	mov	ecx, [vmwsvga2_irq_count]

	mov	dx, [ebx + dev_io]
	VID_WRITE IRQMASK, SVGA_IRQFLAG_ANY_FENCE

	call	svga_fifo_insert_fence

	mov	edi, [ebx + vid_fifo_addr]

	.if VID_DEBUG
		DEBUG "POST FIFO FENCE:"
		call	svga_fifo_print$
	.endif

	# original behaviour:
	# write to SYNC (which sets BUSY to 1), then poll BUSY, to drain the
	# FIFO.

	# in: ebx, dx, fs:edi
	call	svga_fifo_sync$

	VID_WRITE IRQMASK, 0
	cmp	ecx, [vmwsvga2_irq_count]
	jz	92f

	OK
0:	pop	fs
	ret

92:	printlnc 12, "Error - no IRQ"
	jmp	0b
	ret

91:	printlnc 12, "No IRQ capability"
	jmp	0b


################################################################

################################################################
# Interrupt Service Routine
.data
vmwsvga2_irq_count: .long 0
.text32
vmwsvga2_isr:
	pushad
	push	ds
	push	es
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	mov	dx, [ebx + dev_io]
	add	dx, SVGA_IO_IRQSTATUS
	in	eax, dx	# read IRQ flags
	or	eax, eax
	jz	9f	# not for us
	out	dx, eax	# (?) mark as handled

	incd	[vmwsvga2_irq_count]

	.if VMSVGA2_DEBUG
		printc 0xf5, "VID ISR"
		DEBUG_DWORD eax,"IRQ FLAGS"
	.endif

########################################################################
9:
	# EOI handled by IRQ_SHARING

	pop	es
	pop	ds
	popad	# edx ebx eax
	iret

############################################################################
svga_fifo_print$:
	DEBUG "FIFO"
	DEBUG_DWORD fs:[edi+SVGA_FIFO_MIN], "min"
	DEBUG_DWORD fs:[edi+SVGA_FIFO_MAX], "max"
	DEBUG_DWORD fs:[edi+SVGA_FIFO_NEXT_CMD], "next"
	DEBUG_DWORD fs:[edi+SVGA_FIFO_STOP], "stop"
	call	newline
	ret

# in: ebx = dev
# in: fs:edi = fifo start
# in: dx = dev io
svga_fifo_sync$:
	# advice: do not write REG_SYNC unless FIFO_BUSY is false.
	VID_WRITE SYNC, 1
	mov	dword ptr fs:[edi + SVGA_FIFO_BUSY], 1	# advised
	# causes a hang.

0:	VID_READ BUSY	# triggers async exec of FIFO commands
	.if VID_DEBUG
		DEBUG_DWORD eax,"BUSY.."
	.endif
	or	eax, eax
	jnz	0b
	ret


# in: ebx = device
svga_fifo_insert_fence:
	push_	edx eax fs edi
	mov	edx, SEL_flatDS
	mov	fs, edx

	mov	eax, 8
	call	svga_fifo_reserve$
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

	incd	[fifo_updates$]

1:	pop_	eax esi
	ret

9:	printc 4, "FIFO commit: no reservation"
	jmp	1b


#############################################################################
# Font
.data
svga_font_ptr:	.long 0
.text32
svga_font_init:
	mov	eax, 128 * 4 * 8*16	# 65kb
	call	mallocz
	jc	9f
	mov	[svga_font_ptr], eax
	mov	edi, eax
	mov	esi, [curfont]
	mov	ecx, 128 * 16	# 128 chars, 16 scanlines per char
0:	lodsb
	mov	dl, al
	.rept 8			# 8 dwords for 1 char scanline
	xor	eax, eax
	add	dl, dl		# set carry to highest bit
	sbb	eax, 0		# edx = bit ? -1 : 0
	stosd
	.endr
	loop	0b
	clc
9:	ret

svga_font_deinit:
	xor	eax, eax
	xchg	eax, [svga_font_ptr]
	or	eax, eax
	jz	9f
	call	mfree
0:	ret

# in: al = char
# in: edx = fg color
# in: ebx = bg color
svga_font_draw_8x16:
	movzx	eax, al
	shl	eax, 3+4 + 2	# 8x16 pixels * dword
	add	eax, [svga_font_ptr]

	# in: eax = svgaguest ptr
	# in: ? = width in pixels
	# in: ? = format (color depth)
	call	svga_fifo_define_gmrfb	# adds gmrfb as current

	# in: blit origin x,y
	# in: blit dest x1,y1,x2,y2
	# in: screen id
	call	svga_fifo_blit_from_gmrfb	# blit current gmr fb
	ret


svga_fifo_define_gmrfb:
	ret

svga_fifo_blit_from_gmrfb:
	mov	eax, 5*4
	call	svga_fifo_reserve$
	mov	dword ptr fs:[edi + 0], SVGA_CMD_BLIT_GMRFB_TO_SCREEN
	mov	dword ptr fs:[edi + 4], 0	# x
	mov	dword ptr fs:[edi + 8], 0	# y
	mov	dword ptr fs:[edi + 12], 1024	# w
	mov	dword ptr fs:[edi + 16], 768	# h

	call	svga_fifo_commit$
	ret

#####################################
# Screens
.struct 0
svga_screen_struct_size:.long 0
svga_screen_id:		.long 0
svga_screen_flags:	.long 0
	SVGA_SCREEN_HAS_ROOT		= 1<<0
	SVGA_SCREEN_IS_PRIMARY		= 1<<1
	SVGA_SCREEN_FULLSCREEN_HINT	= 1<<2
svga_screen_width:	.long 0
svga_screen_height:	.long 0
svga_screen_x:		.long 0	# root; ignored if flags.HAS_ROOT == 0
svga_screen_y:		.long 0
SVGA_SCREEN_STRUCT_SIZE = .

.text32
# in: eax = screen id
svga_screen_define:
	push_	fs edi edx
	mov	edx, SEL_flatDS
	mov	fs, edx
	mov	edx, eax
	mov	eax, 4 + SVGA_SCREEN_STRUCT_SIZE
	call	svga_fifo_reserve$
	mov	dword ptr fs:[edi + 0], SVGA_CMD_DEFINE_SCREEN
	mov	dword ptr fs:[edi + 4 + svga_screen_struct_size], SVGA_SCREEN_STRUCT_SIZE
	mov	dword ptr fs:[edi + 4 + svga_screen_id], edx
	mov	dword ptr fs:[edi + 4 + svga_screen_flags], 0b11 # root,primary
	mov	dword ptr fs:[edi + 4 + svga_screen_width], 500#SCREEN_WIDTH / 2
	mov	dword ptr fs:[edi + 4 + svga_screen_height], 100# SCREEN_HEIGHT /2
	mov	dword ptr fs:[edi + 4 + svga_screen_x], 100
	mov	dword ptr fs:[edi + 4 + svga_screen_y], 100
	call	svga_fifo_commit$
	pop_	edx edi fs
	ret

# in: eax = screen id
svga_screen_destroy:
	push_	fs edi edx
	mov	edx, SEL_flatDS
	mov	fs, edx
	mov	edx, eax	# screen id
	mov	eax, 8
	call	svga_fifo_reserve$
	mov	dword ptr fs:[edi + 0], SVGA_CMD_DESTROY_SCREEN
	mov	dword ptr fs:[edi + 4], edx
	call	svga_fifo_commit$
	pop_	edx edi fs
	ret

gmr_definecontinuous:
#	VID_WRITE GMR_ID, 
#	VID_WRITE GMR_DESCRIPTOR, ppn
	ret

#############################################################################
.data
gfx_mode: .byte 0	# = 0 txt mode, 1 = gfx mode
screen_update_old: .long 0
.text32

cmd_gfx:
	lodsd
	lodsd
	or	eax, eax
	jnz	9f


	mov	eax, cs
	and	al, 3
	jz	1f
	call	SEL_kernelCall, 0
1:
	mov	eax, cr3
	push	eax
	mov	eax, [page_directory_phys]
	mov	cr3, eax

	xor	byte ptr [gfx_mode], 1
	jz	init_textmode$

	# enter gfx mode:
	cmp	eax, [esp]
	jz	1f	# already in kernel mode - don't map
	mov	ebx, [vmwsvga_dev]

	# map the device IO to the task's PD
	mov	esi, [page_directory_phys]
	GDT_GET_BASE edx, ds
	sub	esi, edx
	mov	eax, [ebx + vid_fifo_addr]
	shr	eax, 22	# get PDE index
	mov	edx, [esi + eax * 4]	# get FIFO PDE
	mov	ecx, [ebx + vid_fb_addr]
	shr	ecx, 22
	mov	ebx, [esi + ecx * 4]	# get FB PDE
	mov	esi, [esp]	# load task PD
	GDT_GET_BASE ebx, ds
	sub	esi, ebx
	mov	[esi + eax * 4], edx	# map FIFO
	mov	[esi + ecx * 4], ebx	# map FB

1:
	mov	eax, [vmwsvga_dev]
	INVOKEVIRTUAL vid gfx_mode

	mov	eax, [screen_update]
	mov	[screen_update_old], eax


	mov	[curfont], dword ptr offset fonts4k#font_4k_courier #_courier56
	mov	[fontwidth], dword ptr 8
	mov	[fontheight], dword ptr 16
	mov	[gfx_printchar_ptr], dword ptr offset gfx_printchar_8x16

	mov	[screen_update], dword ptr offset svga_txt_screen_update
	println "entered gfx mode"
0:	pop	eax
	mov	cr3, eax
	ret


init_textmode$:
	mov	eax, [screen_update_old]
	mov	[screen_update], eax
	# disable SVGA, return to VGA. (textmode!)
	mov	eax, [vmwsvga_dev]
	INVOKEVIRTUAL vid txt_mode
	println	"entered text mode"
	jmp	0b

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

	.if VID_DEBUG
		call	svga_fifo_print$
	.endif
	DEBUG_DWORD [fifo_updates$]
	call	newline

	pop	fs
	ret

DRIVER_VID_VMSVGA2_SIZE =  . - DRIVER_VID_VMSVGA2_BEGIN
