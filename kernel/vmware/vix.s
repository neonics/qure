.intel_syntax noprefix

.struct 0 # message header
vix_mh_magic:	.long 0
vix_mh_version:	.word 0
vix_mh_msglen:	.long 0
vix_mh_hlen:	.long 0
vix_mh_bodylen:	.long 0
vix_mh_credlen:	.long 0
vix_mh_flags:	.byte 0
	VIX_MH_FLAG_REQUEST			= 0x01
	VIX_MH_FLAG_REPORT_EVENT		= 0x02
	VIX_MH_FLAG_FORWARD_TO_GUEST		= 0x04
	VIX_MH_FLAG_GUEST_RETURNS_STRING	= 0x08
	VIX_MH_FLAG_GUEST_RETURNS_INTEGER_STRING= 0x10
	VIX_MH_FLAG_GUEST_RETURNS_ENCODED_STRING= 0x20
	VIX_MH_FLAG_GUEST_RETURNS_PROPERTY_LIST	= 0x40
	VIX_MH_FLAG_GUEST_RETURNS_BINARY	= 0x80
VIX_MH_STRUCT_SIZE = .	# 23 bytes (align?)


VMWARE_VIX_COMMAND_MAGIC = 0xd00d0001
VMWARE_VIX_COMMAND_VERSION = 5
# server side remote vix (not sure whether IO or network?)
VMWARE_VIX_SERVER_PORT = 61525
VMWARE_VIX_TOOLS_SOCKET_PORT = 61526

VMWARE_VIX_COMMAND_MAX_SIZE = 16*1024*1024	# 16mb...hmm
VMWARE_VIX_COMMAND_MAX_REQUEST_SIZE = 65536

.struct VIX_MH_STRUCT_SIZE # command request header
vix_crqh_opcode:	.long 0
	VIX_COMMAND_VM_POWERON                       = 0
	VIX_COMMAND_VM_POWEROFF                      = 1
	VIX_COMMAND_VM_RESET                         = 2
	VIX_COMMAND_VM_SUSPEND                       = 3
	VIX_COMMAND_RUN_PROGRAM                      = 4
	VIX_COMMAND_GET_PROPERTY                     = 5
	VIX_COMMAND_SET_PROPERTY                     = 6
	VIX_COMMAND_KEYSTROKES                       = 7
	VIX_COMMAND_READ_REGISTRY                    = 8
	VIX_COMMAND_WRITE_REGISTRY                   = 10
	VIX_COMMAND_COPY_FILE_FROM_GUEST_TO_HOST     = 12
	VIX_COMMAND_COPY_FILE_FROM_HOST_TO_GUEST     = 13
	VIX_COMMAND_CREATE_SNAPSHOT                  = 14
	VIX_COMMAND_REMOVE_SNAPSHOT                  = 15
	VIX_COMMAND_REVERT_TO_SNAPSHOT               = 16
	VIX_COMMAND_VM_CLONE                         = 17
	VIX_COMMAND_DELETE_GUEST_FILE                = 18
	VIX_COMMAND_GUEST_FILE_EXISTS                = 19
	VIX_COMMAND_FIND_VM                          = 20
	VIX_COMMAND_CALL_PROCEDURE                   = 21
	VIX_COMMAND_REGISTRY_KEY_EXISTS              = 22
	VIX_COMMAND_WIN32_WINDOW_MESSAGE             = 23
	VIX_COMMAND_CONSOLIDATE_SNAPSHOTS            = 24
	VIX_COMMAND_INSTALL_TOOLS                    = 25
	VIX_COMMAND_CANCEL_INSTALL_TOOLS             = 26
	VIX_COMMAND_UPGRADE_VIRTUAL_HARDWARE         = 27
	VIX_COMMAND_SET_NIC_BANDWIDTH                = 28
	VIX_COMMAND_CREATE_DISK                      = 29
	VIX_COMMAND_CREATE_FLOPPY                    = 30
	VIX_COMMAND_RELOAD_VM                        = 31
	VIX_COMMAND_DELETE_VM                        = 32
	VIX_COMMAND_SYNCDRIVER_FREEZE                = 33
	VIX_COMMAND_SYNCDRIVER_THAW                  = 34
	VIX_COMMAND_HOT_ADD_DISK                     = 35
	VIX_COMMAND_HOT_REMOVE_DISK                  = 36
	VIX_COMMAND_SET_GUEST_PRINTER                = 37
	VIX_COMMAND_WAIT_FOR_TOOLS                   = 38
	VIX_COMMAND_CREATE_RUNNING_VM_SNAPSHOT       = 39
	VIX_COMMAND_CONSOLIDATE_RUNNING_VM_SNAPSHOT  = 40
	VIX_COMMAND_GET_NUM_SHARED_FOLDERS           = 41
	VIX_COMMAND_GET_SHARED_FOLDER_STATE          = 42
	VIX_COMMAND_EDIT_SHARED_FOLDER_STATE         = 43
	VIX_COMMAND_REMOVE_SHARED_FOLDER             = 44
	VIX_COMMAND_ADD_SHARED_FOLDER                = 45
	VIX_COMMAND_RUN_SCRIPT_IN_GUEST              = 46
	VIX_COMMAND_OPEN_VM                          = 47
	VIX_COMMAND_GET_DISK_PROPERTIES              = 48
	VIX_COMMAND_OPEN_URL                         = 49
	VIX_COMMAND_GET_HANDLE_STATE                 = 50
	VIX_COMMAND_SET_HANDLE_STATE                 = 51
	VIX_COMMAND_CREATE_WORKING_COPY              = 55 # DELETE this when we switch remote foundry to VIM
	VIX_COMMAND_DISCARD_WORKING_COPY             = 56 # DELETE this when we switch remote foundry to VIM
	VIX_COMMAND_SAVE_WORKING_COPY                = 57 # DELETE this when we switch remote foundry to VIM
	VIX_COMMAND_CAPTURE_SCREEN                   = 58
	VIX_COMMAND_GET_VMDB_VALUES                  = 59
	VIX_COMMAND_SET_VMDB_VALUES                  = 60
	VIX_COMMAND_READ_XML_FILE                    = 61
	VIX_COMMAND_GET_TOOLS_STATE                  = 62
	VIX_COMMAND_CHANGE_SCREEN_RESOLUTION         = 69
	VIX_COMMAND_DIRECTORY_EXISTS                 = 70
	VIX_COMMAND_DELETE_GUEST_REGISTRY_KEY        = 71
	VIX_COMMAND_DELETE_GUEST_DIRECTORY           = 72
	VIX_COMMAND_DELETE_GUEST_EMPTY_DIRECTORY     = 73
	VIX_COMMAND_CREATE_TEMPORARY_FILE            = 74
	VIX_COMMAND_LIST_PROCESSES                   = 75
	VIX_COMMAND_MOVE_GUEST_FILE                  = 76
	VIX_COMMAND_CREATE_DIRECTORY                 = 77
	VIX_COMMAND_CHECK_USER_ACCOUNT               = 78
	VIX_COMMAND_LIST_DIRECTORY                   = 79
	VIX_COMMAND_REGISTER_VM                      = 80
	VIX_COMMAND_UNREGISTER_VM                    = 81
	VIX_CREATE_SESSION_KEY_COMMAND               = 83
	VMXI_HGFS_SEND_PACKET_COMMAND                = 84
	VIX_COMMAND_KILL_PROCESS                     = 85
	VIX_VM_FORK_COMMAND                          = 86
	VIX_COMMAND_LOGOUT_IN_GUEST                  = 87
	VIX_COMMAND_READ_VARIABLE                    = 88
	VIX_COMMAND_WRITE_VARIABLE                   = 89
	VIX_COMMAND_CONNECT_DEVICE                   = 92
	VIX_COMMAND_IS_DEVICE_CONNECTED              = 93
	VIX_COMMAND_GET_FILE_INFO                    = 94
	VIX_COMMAND_SET_FILE_INFO                    = 95
	VIX_COMMAND_MOUSE_EVENTS                     = 96
	VIX_COMMAND_OPEN_TEAM                        = 97
	/* DEPRECATED VIX_COMMAND_FIND_HOST_DEVICES                = 98 */
	VIX_COMMAND_ANSWER_MESSAGE                   = 99
	VIX_COMMAND_ENABLE_SHARED_FOLDERS            = 100
	VIX_COMMAND_MOUNT_HGFS_FOLDERS               = 101
	VIX_COMMAND_HOT_EXTEND_DISK                  = 102

	VIX_COMMAND_GET_VPROBES_VERSION              = 104
	VIX_COMMAND_GET_VPROBES                      = 105
	VIX_COMMAND_VPROBE_GET_GLOBALS               = 106
	VIX_COMMAND_VPROBE_LOAD                      = 107
	VIX_COMMAND_VPROBE_RESET                     = 108

	VIX_COMMAND_LIST_USB_DEVICES                 = 109
	VIX_COMMAND_CONNECT_HOST                     = 110

	VIX_COMMAND_CREATE_LINKED_CLONE              = 112

	VIX_COMMAND_STOP_SNAPSHOT_LOG_RECORDING      = 113
	VIX_COMMAND_STOP_SNAPSHOT_LOG_PLAYBACK       = 114


	VIX_COMMAND_SAMPLE_COMMAND                   = 115

	VIX_COMMAND_GET_GUEST_NETWORKING_CONFIG      = 116
	VIX_COMMAND_SET_GUEST_NETWORKING_CONFIG      = 117

	VIX_COMMAND_FAULT_TOLERANCE_REGISTER         = 118
	VIX_COMMAND_FAULT_TOLERANCE_UNREGISTER       = 119
	VIX_COMMAND_FAULT_TOLERANCE_CONTROL          = 120
	VIX_COMMAND_FAULT_TOLERANCE_QUERY_SECONDARY  = 121

	VIX_COMMAND_VM_PAUSE                         = 122
	VIX_COMMAND_VM_UNPAUSE                       = 123
	VIX_COMMAND_GET_SNAPSHOT_LOG_INFO            = 124
	VIX_COMMAND_SET_REPLAY_SPEED                 = 125

	VIX_COMMAND_ANSWER_USER_MESSAGE              = 126
	VIX_COMMAND_SET_CLIENT_LOCALE                = 127

	VIX_COMMAND_GET_PERFORMANCE_DATA             = 128

	VIX_COMMAND_REFRESH_RUNTIME_PROPERTIES       = 129

	VIX_COMMAND_GET_SNAPSHOT_SCREENSHOT          = 130
	VIX_COMMAND_ADD_TIMEMARKER                   = 131

	VIX_COMMAND_WAIT_FOR_USER_ACTION_IN_GUEST    = 132
	VIX_COMMAND_VMDB_END_TRANSACTION             = 133
	VIX_COMMAND_VMDB_SET                         = 134

	VIX_COMMAND_CHANGE_VIRTUAL_HARDWARE          = 135

	VIX_COMMAND_HOT_PLUG_CPU                     = 136
	VIX_COMMAND_HOT_PLUG_MEMORY                  = 137
	VIX_COMMAND_HOT_ADD_DEVICE                   = 138
	VIX_COMMAND_HOT_REMOVE_DEVICE                = 139

	VIX_COMMAND_DEBUGGER_ATTACH                  = 140
	VIX_COMMAND_DEBUGGER_DETACH                  = 141
	VIX_COMMAND_DEBUGGER_SEND_COMMAND            = 142

	VIX_COMMAND_GET_RECORD_STATE                 = 143
	VIX_COMMAND_SET_RECORD_STATE                 = 144
	VIX_COMMAND_REMOVE_RECORD_STATE              = 145
	VIX_COMMAND_GET_REPLAY_STATE                 = 146
	VIX_COMMAND_SET_REPLAY_STATE                 = 147
	VIX_COMMAND_REMOVE_REPLAY_STATE              = 148

	VIX_COMMAND_CANCEL_USER_PROGRESS_MESSAGE     = 150

	VIX_COMMAND_GET_VMX_DEVICE_STATE             = 151

	VIX_COMMAND_GET_NUM_TIMEMARKERS              = 152
	VIX_COMMAND_GET_TIMEMARKER                   = 153
	VIX_COMMAND_REMOVE_TIMEMARKER                = 154

	VIX_COMMAND_SET_SNAPSHOT_INFO                = 155
	VIX_COMMAND_SNAPSHOT_SET_MRU                 = 156

	VIX_COMMAND_LOGOUT_HOST                      = 157

	VIX_COMMAND_HOT_PLUG_BEGIN_BATCH             = 158
	VIX_COMMAND_HOT_PLUG_COMMIT_BATCH            = 159

	VIX_COMMAND_TRANSFER_CONNECTION              = 160
	VIX_COMMAND_TRANSFER_REQUEST                 = 161
	VIX_COMMAND_TRANSFER_FINAL_DATA              = 162

	VIX_COMMAND_ADD_ROLLING_SNAPSHOT_TIER        = 163
	VIX_COMMAND_REMOVE_ROLLING_SNAPSHOT_TIER     = 164
	VIX_COMMAND_LIST_ROLLING_SNAPSHOT_TIER       = 165

	VIX_COMMAND_ADD_ROLLING_SNAPSHOT_TIER_VMX    = 166
	VIX_COMMAND_REMOVE_ROLLING_SNAPSHOT_TIER_VMX = 167
	VIX_COMMAND_LIST_ROLLING_SNAPSHOT_TIER_VMX   = 168

	VIX_COMMAND_LIST_FILESYSTEMS                 = 169

	VIX_COMMAND_CHANGE_DISPLAY_TOPOLOGY          = 170

	VIX_COMMAND_SUSPEND_AND_RESUME               = 171

	VIX_COMMAND_REMOVE_BULK_SNAPSHOT             = 172
	VIX_COMMAND_COPY_FILE_FROM_READER_TO_GUEST   = 173
	VIX_COMMAND_GENERATE_NONCE                   = 174

	VIX_COMMAND_CHANGE_DISPLAY_TOPOLOGY_MODES    = 175

	/*
	* HOWTO: Adding a new Vix Command. Step 2a.
	*
	* Add a new ID for your new function prototype here. BE CAREFUL. The
	* OFFICIAL list of id's is in the bfg-main tree in bora/lib/public/vixCommands.h.
	* When people add new command id's in different tree they may collide and use
	* the same ID values. This can merge without conflicts and cause runtime bugs.
	* Once a new command is added here a command info field needs to be added
	* in bora/lib/foundryMsg. as well.
	*/
	VIX_COMMAND_LAST_NORMAL_COMMAND              = 176

	VIX_TEST_UNSUPPORTED_TOOLS_OPCODE_COMMAND    = 998
	VIX_TEST_UNSUPPORTED_VMX_OPCODE_COMMAND      = 999

vix_crqh_flags:		.long 0
	VIX_REQMSG_FLAG_ONLY_RELOAD_NETWORKS		= 0x01
	VIX_REQMSG_FLAG_RETURN_ON_INITIATING_TOOLS_UPGRADE= 0x02
	VIX_REQMSG_FLAG_RUN_IN_ANY_VMX_STATE		= 0x04
	VIX_REQMSG_FLAG_REQUIRES_INTERACTIVE_ENVIRONMENT= 0x08
	VIX_REQMSG_FLAG_INCLUDES_AUTH_DATA_V1		= 0x10
vix_crqh_timeout:	.long 0
vix_crqh_cookie:	.long 0,0
vix_crqh_cid:		.long 0	# client handle id 'for remote case'
vix_crqh_ucredtype:	.long 0 # user credential type
	VIX_USER_CRED_NONE			= 0
	VIX_USER_CRED_NAME_PASS			= 1
	VIX_USER_CRED_ANON			= 2
	VIX_USER_CRED_ROOT			= 3
	VIX_USER_CRED_NAME_PASS_OBFUSCATED	= 4
	VIX_USER_CRED_CONSOLE_USER		= 5
	VIX_USER_CRED_HOST_CONFIG_SECRET	= 6
	VIX_USER_CRED_HOST_CONFIG_HASHED_SECRET	= 7
	VIX_USER_CRED_NAMED_INTERACTIVE_USER	= 8

.struct 0
vix_prop_id:	.long 0	# int
	VIX_PROPERTY_NONE			= 0
	VIX_PROPERTY_META_DATA_CONTAINER	= 2	# handle types
	# VIX_HANDLETYPE_HOST properties
	VIX_PROPERTY_HOST_HOSTTYPE		= 50	
	VIX_PROPERTY_HOST_API_VERSION		= 51

	# VIX_HANDLETYPE_VM properties
	VIX_PROPERTY_VM_NUM_VCPUS		= 101
	VIX_PROPERTY_VM_VMX_PATHNAME		= 103
	VIX_PROPERTY_VM_VMTEAM_PATHNAME		= 105
	VIX_PROPERTY_VM_MEMORY_SIZE		= 106
	VIX_PROPERTY_VM_READ_ONLY		= 107
	VIX_PROPERTY_VM_IN_VMTEAM		= 128
	VIX_PROPERTY_VM_POWER_STATE		= 129
	VIX_PROPERTY_VM_TOOLS_STATE		= 152
	VIX_PROPERTY_VM_IS_RUNNING		= 196
	VIX_PROPERTY_VM_SUPPORTED_FEATURES	= 197
	VIX_PROPERTY_VM_GUEST_TEMP_DIR_PROPERTY	= 203	# opensource
	VIX_PROPERTY_VM_IS_RECORDING		= 236
	VIX_PROPERTY_VM_IS_REPLAYING		= 237

	/* Result properties; these are returned by various procedures */
	VIX_PROPERTY_JOB_RESULT_ERROR_CODE	= 3000
	VIX_PROPERTY_JOB_RESULT_VM_IN_GROUP	= 3001
	VIX_PROPERTY_JOB_RESULT_USER_MESSAGE	= 3002
	VIX_PROPERTY_JOB_RESULT_EXIT_CODE	= 3004
	VIX_PROPERTY_JOB_RESULT_COMMAND_OUTPUT	= 3005
	VIX_PROPERTY_JOB_RESULT_HANDLE		= 3010
	VIX_PROPERTY_JOB_RESULT_GUEST_OBJECT_EXISTS	= 3011
	VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_ELAPSED_TIME	= 3017
	VIX_PROPERTY_JOB_RESULT_GUEST_PROGRAM_EXIT_CODE	= 3018
	VIX_PROPERTY_JOB_RESULT_ITEM_NAME	= 3035
	VIX_PROPERTY_JOB_RESULT_FOUND_ITEM_DESCRIPTION	= 3036
	VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_COUNT	= 3046
	VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_HOST	= 3048
	VIX_PROPERTY_JOB_RESULT_SHARED_FOLDER_FLAGS	= 3049
	VIX_PROPERTY_JOB_RESULT_PROCESS_ID	= 3051
	VIX_PROPERTY_JOB_RESULT_PROCESS_OWNER	= 3052
	VIX_PROPERTY_JOB_RESULT_PROCESS_COMMAND	= 3053
	VIX_PROPERTY_JOB_RESULT_FILE_FLAGS	= 3054
	VIX_PROPERTY_JOB_RESULT_PROCESS_START_TIME	= 3055
	VIX_PROPERTY_JOB_RESULT_VM_VARIABLE_STRING	= 3056
	VIX_PROPERTY_JOB_RESULT_PROCESS_BEING_DEBUGGED	= 3057
	VIX_PROPERTY_JOB_RESULT_SCREEN_IMAGE_SIZE	= 3058
	VIX_PROPERTY_JOB_RESULT_SCREEN_IMAGE_DATA	= 3059
	VIX_PROPERTY_JOB_RESULT_FILE_SIZE	= 3061
	VIX_PROPERTY_JOB_RESULT_FILE_MOD_TIME	= 3062

	/* Event properties; these are sent in the moreEventInfo for some events. */
	VIX_PROPERTY_FOUND_ITEM_LOCATION		= 4010

	/* VIX_HANDLETYPE_SNAPSHOT properties */
	VIX_PROPERTY_SNAPSHOT_DISPLAYNAME		= 4200
	VIX_PROPERTY_SNAPSHOT_DESCRIPTION		= 4201
	VIX_PROPERTY_SNAPSHOT_POWERSTATE		= 4205
	VIX_PROPERTY_SNAPSHOT_IS_REPLAYABLE		= 4207

	/* VMX properties. */
	VIX_PROPERTY_VMX_VERSION		= 4400	# opensource
	VIX_PROPERTY_VMX_PRODUCT_NAME		= 4401	# opensource
	VIX_PROPERTY_VMX_VIX_FEATURES		= 4402	# opensource

	/* GuestOS and Tools properties. */
	VIX_PROPERTY_GUEST_TOOLS_VERSION	= 4500	# opensource
	VIX_PROPERTY_GUEST_TOOLS_API_OPTIONS	= 4501	# opensource
		VIX_TOOLSFEATURE_SUPPORT_GET_HANDLE_STATE = 1
		VIX_TOOLSFEATURE_SUPPORT_OPEN_URL = 2
	VIX_PROPERTY_GUEST_OS_FAMILY		= 4502	# opensource
		GUEST_OS_FAMILY_ANY	= 0x0000
		GUEST_OS_FAMILY_LINUX	= 0x0001
		GUEST_OS_FAMILY_WINDOWS	= 0x0002
		GUEST_OS_FAMILY_WIN9X	= 0x0004
		GUEST_OS_FAMILY_WINNT	= 0x0008
		GUEST_OS_FAMILY_WIN2000	= 0x0010
		GUEST_OS_FAMILY_WINXP	= 0x0020
		GUEST_OS_FAMILY_WINNET	= 0x0040
		GUEST_OS_FAMILY_NETWARE	= 0x0080

	VIX_PROPERTY_GUEST_OS_VERSION		= 4503	# opensource
	VIX_PROPERTY_GUEST_OS_PACKAGE_LIST	= 4504	# opensource
	VIX_PROPERTY_GUEST_NAME			= 4505	# opensource
	VIX_PROPERTY_GUEST_POWER_OFF_SCRIPT	= 4506	# opensource
	VIX_PROPERTY_GUEST_POWER_ON_SCRIPT	= 4507	# opensource
	VIX_PROPERTY_GUEST_RESUME_SCRIPT	= 4508	# opensource
	VIX_PROPERTY_GUEST_SUSPEND_SCRIPT	= 4509	# opensource
	VIX_PROPERTY_GUEST_TOOLS_PRODUCT_NAM	= 4511	# opensource
	VIX_PROPERTY_FOREIGN_VM_TOOLS_VERSION	= 4512	# opensource
	VIX_PROPERTY_VM_DHCP_ENABLED		= 4513	# opensource
	VIX_PROPERTY_VM_IP_ADDRESS		= 4514	# opensource
	VIX_PROPERTY_VM_SUBNET_MASK		= 4515	# opensource
	VIX_PROPERTY_VM_DEFAULT_GATEWAY		= 4516	# opensource
	VIX_PROPERTY_VM_DNS_SERVER_DHCP_ENABLED	= 4517	# opensource
	VIX_PROPERTY_VM_DNS_SERVER		= 4518	# opensource
	VIX_PROPERTY_GUEST_TOOLS_WORD_SIZE	= 4519	# opensource
	VIX_PROPERTY_GUEST_OS_VERSION_SHORT	= 4520	# opensource

	VIX_PROPERTY_GUEST_SHAREDFOLDERS_SHARES_PATH		= 4525

	/* Virtual machine encryption properties */
	VIX_PROPERTY_VM_ENCRYPTION_PASSWORD		= 7001


vix_prop_type:	.long 0	# int
	VIX_PROPERTY_TYPE_ANY	= 0
	VIX_PROPERTY_TYPE_INT	= 1
	VIX_PROPERTY_TYPE_STRING= 2
	VIX_PROPERTY_TYPE_BOOL	= 3
	VIX_PROPERTY_TYPE_HANDLE= 4
	VIX_PROPERTY_TYPE_INT64	= 5
	VIX_PROPERTY_TYPE_BLOB	= 6

# union {bool, char, int, int64, vixhandle, struct{unsighed char*,int} blob, void} value
	# VIX_HANDLETYPE_:
	# NONE = 0
	# HOST = 2
	# VM = 3
	# NETWORK = 5
	# JOB = 6
	# SNAPSHOT = 7
	# PROPERTY_LIST = 9
	# METADATA_CONTAINER = 11
vix_prop_value:	.long 0,0 # assume max value size(64)
vix_prop_isdirty:.byte 0	# bool
vix_prop_isSensitive: .byte 0	# bool
vix_prop_next:	.long 0	# ptr
VIX_PROPERTY_VALUE_STRUCT_SIZE = .
# property:
	# properties serialized:
	# header:
	#  id: .long (guess)
	#  type: .lon (guess)
	#  value_len: .long (4 bytes hardcoded)
	#
	# Then, depending on property type:
	# VIX_PROPERTYTYPE_INTEGER: 4
	# VIX_PROPERTYTYPE_STRING: strlen+1
	# VIX_PROPERTYTYPE_BOOL: 1
	# VIX_PROPERTYTYPE_INT64: 8
	# VIX_PROPERTYTYPE_BLOB: blobvalue.blobsize
	# VIX_PROPERTYTYPE_POINTER: 8

.data
	.macro VIX_PROP_S id, val
		.long VIX_PROPERTY_\id
		.long VIX_PROPERTY_TYPE_STRING
		.long 1111f - 1110f
	1110:	.asciz "\val"
	1111:
	.endm

	.macro VIX_PROP_I id, val
		.long VIX_PROPERTY_\id
		.long VIX_PROPERTY_TYPE_INT
		.long \val
	.endm


vix_tools_state$:
VIX_PROP_S GUEST_OS_VERSION, "QuRe"	# os name full
VIX_PROP_S GUEST_OS_VERSION_SHORT, "QuRe" # os name
VIX_PROP_S GUEST_TOOLS_PRODUCT_NAM, "QuRe VMWare Tools" # product short name
VIX_PROP_S GUEST_TOOLS_VERSION, "32768"
VIX_PROP_S GUEST_NAME, "Qure Guest"
VIX_PROP_I GUEST_TOOLS_API_OPTIONS (VIX_TOOLSFEATURE_SUPPORT_OPEN_URL)
VIX_PROP_I GUEST_OS_FAMILY GUEST_OS_FAMILY_ANY
# S GUEST_OS_PACKAGE_LIST
# GUEST_POWER_OFF_SCRIPT
# GUEST_RESUME_SCRIPT
# GUEST_POWER_ON_SCRIPT
# GUEST_SUSPEND_SCRIPT
# VM_GUEST_TEMP_DIR_PROPERTY
VIX_PROP_I GUEST_TOOLS_WORD_SIZE, 4
# TODO: shared folders UNC path (hgfs)

VIX_TOOLS_STATE_PROPLIST_SIZE = . - vix_tools_state$


.struct VIX_MH_STRUCT_SIZE # command response header
vix_crph_cookie:	.long 0,0
vix_crph_flags:		.long 0
	VIX_RESP_FLAG_SOFT_POWER_OP	= 0x1
	VIX_RESP_FLAG_EXTENDED_RESULT_V1= 0x2
	VIX_RESP_FLAG_TRUNCATED		= 0x4
vix_crph_duration:	.long 0
vix_crph_error:		.long 0
vix_crph_error2:	.long 0
vix_crph_errdatalen:	.long 0





	
.text32

# call this when the rpc in message starts with "Vix_".
# in: esi = rpcin data
# in: ecx = rpc in data len
# in data format: 'Vix_1_XXX "16 hex",0, VIX_COMMAND_PACKET
vmware_vix_handle_rpcin:
	push	edi

# Check relayed command:
	LOAD_TXT "Vix_1_Relayed_Command ", edi
	push_	ecx esi
	mov	ecx, 22
	repz	cmpsb
	pop_	esi ecx
	jnz	1f 

	printlnc 0xf0, "received Vix relayed command: "
	add	esi, 22
	sub	ecx, 22

	push	ecx
	mov	ecx, 16 + 2	# 16 hex digits + " + "
	call	nprint_		# advances esi
	pop	ecx
	sub	ecx, 18

	# esi, ecx now point to start of VIX_COMMAND_PACKET.

	call	vmware_vix_handle	# in/out: esi, ecx

	clc
0:	pop	edi
	ret

# next check: nop
1:	
	printc 3, "vix: unimplemented response"
	stc
	jmp	0b

# in: esi, ecx = VIX command packet
vmware_vix_handle:
	push_	eax edx
	lodsb
	cmp	al, 0
	jnz	9f

	# vix message header

	mov	edx, esi
	lodsd
	DEBUG_DWORD eax,"mh magic"
	cmp	eax, VMWARE_VIX_COMMAND_MAGIC
	jnz	9f
	lodsw
	DEBUG_WORD ax,"version"	# 5
	lodsd
	DEBUG_DWORD eax,"msglen"	# 0x33
	lodsd
	DEBUG_DWORD eax,"hlen"		# 0x33
	lodsd
	DEBUG_DWORD eax,"blen"		# 0
	lodsd
	DEBUG_DWORD eax,"clen"		# 0
	lodsb
	DEBUG_BYTE al, "flags"		# 0x41: property list, request
	call	newline
	
	# vix command request header

	lodsd
	DEBUG_DWORD eax,"req opcode"
	lodsd
	DEBUG_DWORD eax,"req flags"
	lodsd
	DEBUG_DWORD eax,"req timeout"
	lodsd
	DEBUG_DWORD eax,"req cookie"
	lodsd
	DEBUG_DWORD eax,"req cookie2"
	lodsd
	DEBUG_DWORD eax,"req cid"
	lodsd
	DEBUG_DWORD eax,"req ucredt"

	mov	esi, edx
	call	newline

# Check for GET_TOOLS_STATE
	cmp	dword ptr [esi + vix_crqh_opcode], VIX_COMMAND_GET_TOOLS_STATE
	jnz	1f

	printlnc 15, "VIX Command: get tools state"

	push	edi

        mov     ecx, VIX_TOOLS_STATE_PROPLIST_SIZE
	
	mov	eax, ecx
	call	base64_encoded_len
	add	eax, 3	# 'OK '
	call	mallocz
	# eax = return value
	mov	edi, eax

	mov	dword ptr [edi], 'O'|('K'<<8)|(' '<<24)
	DEBUG_DWORD edi, "BUF PRE"
	DEBUG_BYTE [edi+0]
	DEBUG_BYTE [edi+1]
	DEBUG_BYTE [edi+2]
	add	edi, 3

        mov     esi, offset vix_tools_state$
        call    base64_encode   # in: esi,ecx,edi; out: edi?, ecx

	mov	esi, eax
	DEBUG_DWORD eax, "BUF POST"
	mov [esi+2], byte ptr ' ' # STRANGE!@
	DEBUGS esi, "returning: "
		pushcolor 0xf3
		push_ esi ecx
		call nprint_
		pop_ ecx esi
		DEBUG_DWORD ecx
		DEBUG_BYTE [esi+2]
		popcolor


	pop	edi
	clc

0:	pop_	edx eax
	ret

9:	# malformed packet
	printlnc 4, "VIX malformed packet"
# Last check: no match.
1:	stc
	jmp	0b

