#############################################################################
.intel_syntax noprefix
.text32

# 32 Bit Paging (no PAE - physical address extension)
#
# Virtual memory address: each address consists of 32 bits:
#
# DDDDDDDDDDTTTTTTTTTToooooooooooo
#
# 10 bits (31:22) page Directory entry index
# 10 bits (20:11) page Table entry index
# 12 bits (11:0)  Offset in page
#
# Page Directory
#
# The entire page directory covers 4 GB of virtual address space, split
# into 1024 entries. Each entry thus refers to 4 MB of virtual address space:
# entry 0: 0..4Mb
# entry 1: 4..8Mb
# ..
# entry 1023: 4GB - 4Mb .. 4GB
#
# Each entry is the physical address of a page table mapping that specific
# range, except the low 12 bits (4096), which are flags:

# PDEs (Page Directory Entries) can be 4 bytes or 8 bytes (64 bit),
# depending on CR0.PAE.
#
# PDEs can either reference a PTE (Page Table Entry) that maps a page,
# in which case PDE_FLAG_S=0,
# or the PDE can map a page directly, when PDE_FLAG_S=1, which is only
# available when CR4.PSE=1. In both cases,
# PDE_FLAG_P (present) = bit 0 must be 1, otherwise the entry is ignored.
#
# Format for 32 bit PDE mapping a 4 MB page:
#   31:22: bits 31:22 of address of 2MB page frame
#   21:17: reserved (0)
#   16:13: bits 39:32: of address
#   12:    PAT (page attribute table - memory type)
#   11:9:  ignored (PDE_FLAG_AVAIL)
#   8:     PDE_FLAG_G - global.
#   7:     PDE_FLAG_S: 1
#   The other flags are described below.
#
# When PDE_FLAG_S=0, the PDE references a PTE.
# In this case, the format is:
#
#   31:12: address of page table (low12 bits=0: 4kb aligned)
#   11:8:  ignored (including PDE_FLAG_G at 8)
#   7:     PDE_FLAG_S=0
#   The rest defined below.
PDE_FLAG_PAT	= 1 << 12	# mem type for 4mb page if PAT enabl; 0 otherw.
PDE_FLAG_AVAIL	= 0b000 << 9	# ignored - free for OS usage
PDE_FLAG_G	= 1 << 8	# global, when CR4.PGE=1, otherwise ignored.
PDE_FLAG_S	= 1 << 7	# page size 0=references PTE, 1=map 4Mb page
PDE_FLAG_0	= 0 << 6	# reserved
PDE_FLAG_A	= 1 << 5	# accessed
PDE_FLAG_D	= 1 << 4	# cache disabled
PDE_FLAG_W	= 1 << 3	# write through
PDE_FLAG_U	= 1 << 2	# user/supervisor: 0=CPL3 access not allowed
PDE_FLAG_R	= 1 << 1	# 1=read/write, 0=read only dep CPL, CR0.WP
PDE_FLAG_P	= 1 << 0	# present

# Page Table
#
# A page table maps 4MB virtual address space, consisting of 1024 entries,
# each referring to a page (4KB) of physical memory.
# Each page table entry (PTE) maps 4kb of memory.
#
# The low 12 bits are flags:

PTE_FLAG_AVAIL	= 0b000 << 9	# ignored - free for OS use
PTE_FLAG_G	= 1 << 8	# global
PTE_DLAG_0	= 1 << 7	# reserved
PTE_FLAG_D	= 1 << 6	# dirty
PTE_FLAG_A	= 1 << 5	# accessed
PTE_FLAG_C	= 1 << 4	# cache disabled
PTE_FLAG_W	= 1 << 3	# write-through
PTE_FLAG_U	= 1 << 2	# user/supervisor
PTE_FLAG_R	= 1 << 1	# 1=read/write, 0=read only
PTE_FLAG_P	= 1 << 0	# present

# When paging is enabled, all memory addresses are considered to be virtual.
# The top 10 bits are taken to denote the index in the page directory.
# The next 10 bits of the virtual address are taken to be the index into
# the page.
#
# The start of the page directory in physical memory is stored in CR3.
#
# Entries in both the page directory and page tables are 4 bytes each,
# so, index 1 is the dword at offset 4 into the directory or table.
#
# Calculation of the conversion of a virtual to a physical address can
# be expressed as:
#
# ptable_phys = page_directory[ 4 * vaddr >> 22 ] & ~0xfff
# paddr = ptable_phys[ 4 * ( (vaddr >> 12) & ((1<<10)-1) ) ]
# or:
# ptable_phys = (pdir[vaddr>>22<<2]&~0xfff)[(vaddr>>12)&3ff<<2]

#
# PAE (Physical Address Extension) Paging
#
# If CR0.PAE=1 (in addition to CR0.PG=1), 32 bit linear addresses are translated
# to 52 bit physical addresses (4 Petabytes), even though only 4Gb can be
# accessed at any given time.
#
# With PAE, there are 4 internal PDPTE registers loaded from memory pointed
# to by CR3. In this case then, CR3 does not point to the page directory,
# but to four dwords (32 byte aligned), each referencing page directory.
# Format of CR3 in this case:
#   63:32: ignored
#   31:5   physical address of 32-byte aligned page-directory pointer table.
#   4:0    ignored.
#
# The four entries found at the memory that CR3 points to are PDPTEs,
# Page Directory Pointer Tables, each controlling 1Gb of linear address space.
#
# PDPTE format: each PDPTE is 64 bits:

PDPTE_P		= 1 << 0	# present
# 2:1: reserved (0)
PDPTE_PWT	= 1 << 3	# page-level write through
PDPTE_PCD	= 1 << 4	# page-level cache disable
# 8:5: reserved (0)
PDPTE_AVAIL_MASK= 0b11 << 9
# M-1:12: physical address of 4kb page directory (M is max 52)
# 63:M:	reserved, must be 0;

#
# PCIDs - Process Context Identifiers (see CPUID for availability).
#
# When CR4.PCIDE = 0, PCID is 0x000.
# When CR4.PCIDE = 1, PCID is CR3[11:0].
#
# Process Context Identifiers are only available in IA-32e mode,
# so not available in 32 bit or PAE paging.


.data SECTION_DATA_BSS
page_directory_phys:	.long 0
page_directory:		.long 0	# ds relative logical address
page_tables_phys_end:	.long 0
.text32

# This method creates a page directory after the kernel stack top,
# page aligned. Following that, a page table for the first 4 MB of ram.
# Other memory is not mapped, as for a virtual machine with 128Mb ram
# available, the tables required would be 33 * 4Kb = 132 kb ram, which would
# double the kernel memory usage. Instead, when more ram is needed,
# it will be dynamically mapped using the page fault mechanism.
paging_init:
	GDT_GET_BASE edx, ds
	mov	ebx, [kernel_stack_top]
	add	ebx, edx

	# page (4kb) align
	add	ebx, 0x0fff
	and	ebx, 0xfffff000
	mov	[page_directory_phys], ebx
	DEBUG_DWORD ebx, "page_directory phys"

	# have edi point to the ds relative address of the page directory
	mov	edi, ebx
	sub	edi, edx
	mov	[page_directory], edi

	# initialize page directory: each entry (indirectly) references 4 MB

	# clear the page directory:
	xor	eax, eax
	mov	ecx, 1024
	rep	stosd

	# first page table 4k after page directory:
	lea	eax, [ebx + 4096 | PDE_FLAG_R | PDE_FLAG_U | PDE_FLAG_P]
	mov	[edi - 4096], eax	# set first PDE
	DEBUG_DWORD eax, "first page table phys"

	lea	eax, [ebx + 8192]
	mov	[page_tables_phys_end], eax

	# initialze the first page table: identity mapping, start at phys addr 0
	mov	eax, PTE_FLAG_R | PTE_FLAG_U | PTE_FLAG_P
	mov	ecx, 1024
0:	stosd
	add	eax, 4096
	loop	0b

	I "Enabling paging"
	call	paging_enable
	OK
	call paging_show_usage
	ret

paging_enable:
	# tell the CPU where to find the page directory:
	mov	cr3, ebx

#	# see CPUID for availability:
#	CR4_PAE = 1 << 5	# physical address extension (64gb,36 addr bits)
#	CR4_PSE = 1 << 4	# page size extenstion (guess)
#	reset PSE (page size extension?)
	mov	ebx, cr4
	or	ebx, 1 << 4	# set PSE
	mov	cr4, ebx

	# enable paging
	mov	eax, cr0
	or	eax, 0x80000000	# CR0_PAGING = 1 << 31
	mov	cr0, eax
	ret

paging_disable:
	mov	eax, cr0
	and	eax, ~0x80000000
	mov	cr0, eax

	# garbage the page directory and the first page table:
	sub	edi, 8192
	xor	eax, eax
	mov	ecx, 2048
	rep	stosd

	mov	cr3, eax
	ret

##############################################################################

# in: eax = physical address to identity map
# in: ecx = size to map
paging_idmap_4m:
#DEBUG "paging_idmap"
#DEBUG_DWORD ecx,"size"
#DEBUG_DWORD eax,"addr"
	push_	edx eax ecx
#	add	ecx, 1024 * 4096 - 1
	shr	ecx, 22		# divide by 4m; ecx is nr of 4m pages.

	mov	edx, eax
	and	edx, ~4095	# mask low 12 bits
	shr	eax, 20		# divide by 1Mb (/4Mb * sizeof(dword))
	and	al, ~3		# align to 4Mb
#DEBUG_DWORD ecx,"#4m pages"
#DEBUG_DWORD edx,"addr"
#DEBUG_DWORD eax,"PDE idx"
#call newline
	/*
push_ edx eax
printc 11, "paging: identity map "
xor	edx, edx
mov	eax, [esp + 8]	# orig ecx
call	print_size
printc 11, " @ "
mov	edx, [esp + 4]
call	printhex8
call	newline
pop_ eax edx
*/
	# eax is index into page directory referring to the phys addr.
	# edx is the phys addr.
	add	eax, [page_directory]
	or	dx, PDE_FLAG_R|PDE_FLAG_U|PDE_FLAG_P| PDE_FLAG_S
0:	mov	[eax], edx
	add	eax, 4
	add	edx, 4096 * 1024
#	loop	0b

	#call	paging_show_usage

	pop_	ecx eax edx
	ret



# in: eax = page physical address
# in: esi = PDE physical address
paging_idmap_page:
	push_	eax ecx edx esi

	GDT_GET_BASE edx, ds

	mov	ecx, eax
	shr	ecx, 22	# divide by 4mb for index

	sub	esi, edx
	mov	esi, [esi + ecx * 4]	# get PTE ptr

		or	esi, esi
		jz	9f

	mov	ecx, eax
	and	ecx, ~((1<<22)-1)
	shr	ecx, 12	# shift out the flags

	or	eax, PDE_FLAG_R | PDE_FLAG_U | PDE_FLAG_P
	sub	esi, edx
	mov	[esi + ecx * 4], eax

0:	pop_	esi edx ecx eax
	ret

9:	printc 4, "ERROR: No PTE. PDE: "
	lea	edx, [esi + edx]
	call	printhex8
	call	printspace
	mov	edx, [esp + 4 * 4]
	call	debug_printsymbol
#	int 3
	jmp	0b


# in: eax = physical address
# in: edx = logical address to map physical address onto
# in: ecx = size to map
paging_map_4k:	# XXX FIXME TODO UNFINISHED
	push_	esi edi

	# 4k page dir, for 1024 entries of 4 Gb.
	# first page table follows the page dir: [page_directory] + 4096.
	# quick hack: we add a second page table at [page_directory} = 8192.

	# first initialize the page table:
	mov	edi, [page_directory]
	add	edi, 8192

		add	edi, 4096
		mov	[page_tables_phys_end], edi
		sub	edi, 4096
	
	push_	eax ecx
	mov	ecx, 1024
	and	eax, ~0b111111111111 # mask out low 12 bits for 4mb offset
	or	eax, PTE_FLAG_R|PTE_FLAG_U|PTE_FLAG_P
0:	stosd
	add	eax, 4096
	

	pop_	ecx eax


	shr	eax, 22	# >> (12 + 10) = / (4096 * 1024): 4Mb
	mov	edi, [page_directory_phys]
	add	edi, 8192|PDE_FLAG_R|PDE_FLAG_U|PDE_FLAG_P# edi is address of page table
	# record the page table in the page directory:
	mov	esi, [page_directory]
	# the location in [esi] indicates for which page (eax*4) the table is.
	mov	[esi + eax * 4], edi

	pop_	edi esi
	ret

# in: esi = page-dir-phys
paging_show_usage1$:
	pushad
	jmp	1f

paging_show_usage:
	pushad
	mov	esi, [page_directory_phys]
1:	GDT_GET_BASE ebx, ds
		DEBUG_DWORD esi, "page_dir_phys"
	sub	esi, ebx
		DEBUG_DWORD esi, "page_dir"
		call newline
	mov	ecx, 1024
0:	lodsd
	test	eax, PDE_FLAG_P
	jz	1f

	print	"PDE "
	mov	edx, 1024
	sub	edx, ecx
	call	printdec32
		call	printspace
		shl	edx, 22
		call	printhex8
		printchar '-'
		add	edx, 1 << 22
		call	printhex8
	mov	edx, eax
	print	" PTE "
	call	printhex8
		call	printspace
		and	edx, ~((1<<22)-1)
		call	printhex8
		mov	edx, eax
		and	edx, (1<<22)-1
		call	printspace
		call	printhex8
	call	newline

	test	eax, PDE_FLAG_S
	jnz	1f	# skip PTE

.if 0##################
	push	eax
	push	esi
	push	ecx
	mov	ecx, 1024
	mov	esi, eax
	and	esi, 0xfffff000
	sub	esi, ebx
5:	lodsd
	test	eax, PTE_FLAG_A
	jz	6f
	mov	edx, 1024
	sub	edx, ecx
	call	printdec32
	call	printspace
6:	loop	5b
	call	newline
	pop	ecx
	pop	esi
	pop	eax
.endif##################

########
	push	ebp
	push	esi
	push	ecx
	mov	ebp, esp
	push	dword ptr 0
	push	dword ptr 0
	push	dword ptr 0

	mov	ecx, 1024
	mov	esi, eax
	and	esi, 0xfffff000
	sub	esi, ebx

2:	lodsd
	test	eax, PTE_FLAG_A
	jnz	4f

	# cur is non-active. check prev:
	cmp	dword ptr [ebp - 4], 0
	jz	3f	# no prev, continue
	# have prev, print range:
	mov	eax, [esi - 8]
	call	8f
	mov	dword ptr [ebp - 4], 0 # reset prev
	jmp	3f

4:	# check prev:
	cmp	dword ptr [ebp - 4], 0
	jnz	3f	# have prev, continue

	# store cur
4:	mov	[ebp -4], eax
	mov	[ebp -8], ecx

3:	loop	2b

####	# final entry check: if last PTE accessed, no printing was done.
	test	eax, PTE_FLAG_A
	jz	3f
	call	8f
####
3:	print " #pages: "
	mov	edx, [ebp - 12]
	call	printdec32
	call	newline
	mov	esp, ebp
	pop	ecx
	pop	esi
	pop	ebp
########


1:	#loop	0b
	dec	ecx
	jnz	0b
	popad
	ret

###
8:	push	edi
	push	ebx
	mov	edi, [ebp - 4]
	mov	ebx, [ebp - 8]

	print "  PTE "
	or	edi, edi
	jz	1f
	mov	edx, 1024
	sub	edx, ebx
	call	printdec32
	print "-"
1:	mov	edx, 1024-1
	sub	edx, ecx
	call	printdec32

	print " ("
	add	edx, ebx
	sub	edx, 1024-1
	call	printdec32
	add	[ebp - 12], edx
	print ") "

	print " phys "
	or	edi, edi
	jz	1f
	mov	edx, edi
	call	printhex8
	print " - "
1:	mov	edx, eax
	call	printhex8

	print " ("
	and	edx, 0xfffff000
	and	edi, 0xfffff000
	sub	edx, edi
	mov	eax, edx
	add	eax, 0x1000
	xor	edx, edx
	call	print_size
	print ")"

	call	newline
	pop	ebx
	pop	edi
	ret


# print contiguous region:
# in: edi = last contigous entry
# in: ebx = nr of contigous entries
# in: [ebp] = 1024-index in PDE
# in: [ebp-4] = ds:PT base
8:	push	edx
	push	esi
	mov	edx, edi
	sub	edx, ebx
	print " PTE "
	call	printdec32
	print " - "
	mov	edx, edi
	call	printdec32
	print " phys "
	mov	esi, [ebp - 4]
	mov	edx, edi
	sub	edx, ebx
	mov	edx, [esi + edx * 4]	# start PTE
	call	printhex8
	print " - "
	mov	edx, [esi + edi * 4]	# end PTE
	call	printhex8
	call	newline
	pop	esi
	pop	edx
	ret

#	# see CPUID for availability:
#	CR4_PAE = 1 << 5	# physical address extension (64gb,36 addr bits)
#	CR4_PSE = 1 << 4	# page size extenstion (guess)
#	reset PSE (page size extension?)
#	mov	ebx, cr4
#	and	ebx, ~0x10	# when set, PDE_FLAG_S available
#	mov	cr4, ebx

# Page faults:
#
# Error code on interrupt 14 (#PF):
#
# bit 0: P (present) fault cause: 0 = page not present; 1=protection violation.
# bit 1: W/R: access causing fault: 0 = read, 1 = write
# bit 2: U/S: origin: 0=supervisor mode (CPL<3), 1=user mode (CPL=3)
# bit 3: RSVD: 0=not, 1=caused by reserved bit set to 1 in paging struct entry.
# bit 4: I/D: instruction/data: 0=not caused, 1=caused by instruction fetch.
# bits 31:5: reserved.

