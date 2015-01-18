.ifndef __DEFINES_INCLUDED
__DEFINES_INCLUDED=1


# .data layout
SECTION_DATA		= 0	# leave at 0 as there is still .data used.
SECTION_DATA_SEMAPHORES	= 1
SECTION_DATA_TLS	= 2
SECTION_DATA_CONCAT	= 3

SECTION_DATA_PCI_DRIVERINFO	= 18
SECTION_DATA_FONTS	= 19
SECTION_DATA_STATS	= 98
SECTION_DATA_BSS	= 99
SECTION_DATA_SIGNATURE	= SECTION_DATA_BSS +1

# .text layout
SECTION_CODE_TEXT16	= 0
SECTION_CODE_DATA16	= 1	# keep within 64k
SECTION_CODE_TEXT32	= 3

.macro INCLUDE file, name=0
.ifnc 0,\name
.text32
.global code_\name\()_start
code_\name\()_start:
.endif
.include "\file"
.ifnc 0,\name
.text32
.global code_\name\()_end
code_\name\()_end:
.endif
.endm


PUSHAD_EDI = 4*0
PUSHAD_ESI = 4*1
PUSHAD_EBP = 4*2
PUSHAD_ESP = 4*3
PUSHAD_EBX = 4*4
PUSHAD_EDX = 4*5
PUSHAD_ECX = 4*6
PUSHAD_EAX = 4*7

.endif
