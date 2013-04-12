.intel_syntax noprefix

# 'Backdoor' access: on read/write from special ports, having eax contain
# a magic number, the VM steps in and treats the IO access as a backdoor call.

VMWARE_BD_PORT = 0x5658	# "VX" (reverse)
VMWARE_BD_MAGIC = 0x564d5868 # "VMXh" (reverse)

# These go in cx
VMWARE_BD_CMD_GET_MHZ			= 1
VMWARE_BD_CMD_APM_FUNCTION		= 2
VMWARE_BD_CMD_GET_DISK_GEO		= 3
VMWARE_BD_CMD_GET_PTR_LOCATION		= 4
VMWARE_BD_CMD_SET_PTR_LOCATION		= 5
VMWARE_BD_CMD_GET_SEL_LENGTH		= 6 # copy..
VMWARE_BD_CMD_GET_NEXT_PIECE		= 7 # ..and..
VMWARE_BD_CMD_SET_SEL_LENGTH		= 8 # ..paste
VMWARE_BD_CMD_GET_VERSION		= 10
VMWARE_BD_CMD_GET_DEVICELISTELEMENT	= 11
VMWARE_BD_CMD_TOGGLED_EVICE		= 12
VMWARE_BD_CMD_GET_GUI_OPTIONS		= 13
VMWARE_BD_CMD_SET_GUI_OPTIONS		= 14
VMWARE_BD_CMD_GET_SCREEN_SIZE		= 15
VMWARE_BD_CMD_MONITOR_CONTROL		= 16
VMWARE_BD_CMD_GET_HW_VERSION		= 17
VMWARE_BD_CMD_OS_NOT_FOUND		= 18
VMWARE_BD_CMD_GET_UUID			= 19
VMWARE_BD_CMD_GET_MEM_SIZE		= 20
VMWARE_BD_CMD_HOSTCOPY			= 21	# dev
VMWARE_BD_CMD_SERVICE_VM		= 22	# prototyping
VMWARE_BD_CMD_GETTIME			= 23	# deprecated
VMWARE_BD_CMD_STOP_CATCHUP		= 24
VMWARE_BD_CMD_PUTCHAR			= 25	# dev
VMWARE_BD_CMD_ENABLE_MSG		= 26	# dev
VMWARE_BD_CMD_GOTO_TCL			= 27	# dev
VMWARE_BD_CMD_INIT_PCIO_PROM		= 28
VMWARE_BD_CMD_INT13			= 29
VMWARE_BD_CMD_MESSAGE			= 30	# rpc
	# these go in high word of ecx
	VMWARE_BD_MSG_TYPE_OPEN		= 0
		VMWARE_CHAN_FLAG_COOKIE		= 0x80000000
		VMWARE_CHAN_MAX_CHANNELS	= 8
		VMWARE_CHAN_MAX_SIZE		= 65536
		VMWARE_CHAN_PROTO_TCLO		= 0x4f4c4354	# "TCLO"
		VMWARE_CHAN_PROTO_RPCI		= 0x49435052	# "RPCI"
	VMWARE_BD_MSG_TYPE_SENDSIZE	= 1
	VMWARE_BD_MSG_TYPE_SENDPAYLOAD	= 2
	VMWARE_BD_MSG_TYPE_RECVSIZE	= 3 #out:edx>>16=SENDSIZE;ebx=size
	VMWARE_BD_MSG_TYPE_RECVPAYLOAD	= 4
	VMWARE_BD_MSG_TYPE_RECVSTATUS	= 5
	VMWARE_BD_MSG_TYPE_CLOSE	= 6

	# returned in high word of ecx
	VMWARE_BD_MSG_ST_SUCCESS	= 1 << 0 #guest can set this bit only!
	VMWARE_BD_MSG_ST_DORECV		= 1 << 1
	VMWARE_BD_MSG_ST_CLOSED		= 1 << 2
	VMWARE_BD_MSG_ST_UNSENT		= 1 << 3 # removed before received
	VMWARE_BD_MSG_ST_CPT		= 1 << 4 # checkpoint
	VMWARE_BD_MSG_ST_POWEROFF	= 1 << 5
	VMWARE_BD_MSG_ST_TIMEOUT	= 1 << 6
	VMWARE_BD_MSG_ST_HB		= 1 << 7 # high bandwidth supported
VMWARE_BD_CMD_RESERVED1			= 31
VMWARE_BD_CMD_RESERVED2			= 32
VMWARE_BD_CMD_RESERVED3			= 33
VMWARE_BD_CMD_IS_ACPI_DISABLED		= 34
VMWARE_BD_CMD_TOE			= 35	# N/A
VMWARE_BD_CMD_IS_MOUSE_ABSOLUTE		= 36
VMWARE_BD_CMD_PATCH_SMBIOS_STRUCTS	= 37
VMWARE_BD_CMD_MAPMEP			= 38	# dev
VMWARE_BD_CMD_ABS_POINTER_DATA		= 39
VMWARE_BD_CMD_ABS_POINTER_STATUS	= 40
VMWARE_BD_CMD_ABS_POINTER_COMMAND	= 41
VMWARE_BD_CMD_TIMER_SPONGE		= 42
VMWARE_BD_CMD_PATCH_ACPI_TABLES		= 43
VMWARE_BD_CMD_DEVEL_FAKE_HARDWARE	= 44	# debug
VMWARE_BD_CMD_GET_HZ			= 45
VMWARE_BD_CMD_GET_TIME_FULL		= 46
VMWARE_BD_CMD_STATE_LOGGER		= 47
VMWARE_BD_CMD_CHECK_FORCE_BIOS_SETUP	= 48
VMWARE_BD_CMD_LAZY_TIMER_EMULATION	= 49
VMWARE_BD_CMD_BOS_BBS			= 50
VMWARE_BD_CMD_V_ASSERT			= 51
VMWARE_BD_CMD_IS_G_OS_DARWIN		= 52
VMWARE_BD_CMD_DEBUG_EVENT		= 53
VMWARE_BD_CMD_OS_NOT_MACOSX_SERVER 	= 54
VMWARE_BD_CMD_GET_TIME_FULL_WITH_LAG	= 55
VMWARE_BD_CMD_ACPI_HOTPLUG_DEVICE	= 56
VMWARE_BD_CMD_ACPI_HOTPLUG_MEMORY	= 57
VMWARE_BD_CMD_ACPI_HOTPLUG_CBRET	= 58
VMWARE_BD_CMD_GET_HOST_VIDEO_MODES	= 59
VMWARE_BD_CMD_ACPI_HOTPLUG_CPU		= 60
VMWARE_BD_CMD_USB_HOTPLUG_MOUSE		= 61
VMWARE_BD_CMD_XPMODE			= 62
VMWARE_BD_CMD_NESTING_CONTROL		= 63
VMWARE_BD_CMD_FIRMWARE_INIT		= 64




# VMWARE_BDOOR_CALL:
# in/out eax, dx: eax, ebx=size, ecx,      edx, esi,          edi
# VMWARE_BDOOR_HB_IN/OUT:
# rep insb/outsb: eax, ebx,      ecx=size, edx, esi=src addr, edi=dst addr, ebp

# retry macro's: when not succes and checkpoint, retry.

# don't use this directly!
.macro VMWARE_BDOOR_RETRY reg, retrylabel, oklabel=0
	test	\reg, VMWARE_BD_MSG_ST_SUCCESS << 16
	.ifc 0,\oklabel
	jnz	99f
	.else
	jnz	\oklabel
	.endif
	test	\reg, VMWARE_BD_MSG_ST_CPT << 16
	jnz	\retrylabel
99:	# out: nz = success; z=error
.endm


.macro VMWARE_BDOOR_CALL retry=0, preserve=0
	.if \preserve != 0
	push	\preserve
	.endif
	mov	eax, VMWARE_BD_MAGIC
	mov	dx, VMWARE_BD_PORT
	.if VMWARE_DEBUG > 1
		DEBUG_REGSTORE
		DEBUG "BDOOR CALL"
		DEBUG_DWORD ecx
	.endif
	in	eax, dx
	.if VMWARE_DEBUG > 1
		DEBUG_REGDIFF
	.endif
	.if \preserve != 0
	pop	\preserve
	.endif
	.ifc 0,\retry
	.else
	VMWARE_BDOOR_RETRY ecx, \retry
	.endif
.endm

.macro VMWARE_BD_MESSAGE
	VMWARE_BDOOR_CALL
.endm

#########################################################
# 'high bandwidth' (rep insb/outsb) calls:
VMWARE_BD_HB_PORT = 0x5659
VMWARE_BD_HB_CMD_MESSAGE = 0
VMWARE_BD_HB_CMD_VASSERT = 1

.macro VMWARE_BDOOR_HB_IN retry=0 preserve=0
	.if \preserve != 0
	push	\preserve
	.endif
	mov	eax, VMWARE_BD_MAGIC
	mov	dx, VMWARE_BD_HB_PORT
	rep	insb
	.if \preserve != 0
	pop	\preserve
	.endif
	.ifc 0,\retry
	.else
	VMWARE_BDOOR_RETRY ebx, \retry
	.endif
.endm

.macro VMWARE_BDOOR_HB_OUT retry=0 preserve=0
	.if \preserve != 0
	push	\preserve
	.endif
	mov	eax, VMWARE_BD_MAGIC
	mov	dx, VMWARE_BD_HB_PORT
	rep	outsb
	.if \preserve != 0
	pop	\preserve
	.endif
	.ifc 0,\retry
	.else
	VMWARE_BDOOR_RETRY ebx, \retry
	.endif
.endm


#############################################################################

