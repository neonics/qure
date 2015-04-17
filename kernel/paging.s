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
PDE_FLAG_RW	= 1 << 1	# 1=read/write, 0=read only dep CPL, CR0.WP
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
PTE_FLAG_0	= 1 << 7	# reserved
PTE_FLAG_D	= 1 << 6	# dirty
PTE_FLAG_A	= 1 << 5	# accessed
PTE_FLAG_C	= 1 << 4	# cache disabled
PTE_FLAG_W	= 1 << 3	# write-through
PTE_FLAG_U	= 1 << 2	# user/supervisor
PTE_FLAG_RW	= 1 << 1	# 1=read/write, 0=read only
PTE_FLAG_P	= 1 << 0	# present

# When paging is enabled, all memory addresses are considered to be virtual.
# The top 10 bits are taken to denote the index in the page directory.
# The next 10 bits of the virtual address are taken to be the index into
# the page table.
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
# but to four dwords (32 byte aligned), each referencing a page directory.
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
.text32

paging_init:
	GDT_GET_BASE edx, ds

	call	malloc_page_phys
	jc	9f
	mov	[page_directory_phys], eax
	mov	edi, eax
	mov	esi, eax	# for paging_* calls
	sub	edi, edx
	mov	[page_directory], edi

	# clear the page directory:
	xor	eax, eax
	mov	ecx, 1024
	rep	stosd


	# initialize page directory: each entry (indirectly) references 4 MB
	# allocate a page for the 0..4mb region
	call	paging_alloc_page_idmap
	jc	9f

	# use this page as the page table for 0..4Mb
	mov	edi, esi
	sub	edi, edx	# PD ds-rel
	or	eax, PDE_FLAG_RW | PDE_FLAG_P
	mov	[edi + 0], eax
	and	eax, 0xfffff000

	# initialize the first page table: identity mapping, start at phys addr 0
	mov	edi, eax
	sub	edi, edx
	mov	eax, PTE_FLAG_RW | PTE_FLAG_P
	mov	ecx, 1024
0:	stosd
	add	eax, 4096
	loop	0b

	# XXX this _MAY_ fail, but unlikely
	# Map the PD: this will allow pages to be mapped.
	mov	eax, esi	# page dir phys
	call	paging_idmap_page	# map the page dir itself

	I "Enabling paging"
	call	paging_enable
	OK
mov eax, cr3
mov [TSS + tss_CR3], eax
mov [TSS_DF + tss_CR3], eax
mov [TSS_PF + tss_CR3], eax
mov [TSS_NP + tss_CR3], eax
call paging_print_pd$
	call	paging_show_struct
	ret

9:	printlnc 4, "paging_init: cannot allocate page"
	ret


paging_enable:
	# tell the CPU where to find the page directory:
	mov	ebx, [page_directory_phys]
	mov	cr3, ebx

#	# see CPUID for availability:
#	CR4_PAE = 1 << 5	# physical address extension (64gb,36 addr bits)
#	CR4_PSE = 1 << 4	# page size extenstion (guess): 4Mb pages (no PD)
#	reset PSE (page size extension?)
	mov	ebx, cr4
	or	ebx, 1 << 4	# set PSE
	mov	cr4, ebx

	# enable paging and write protection
	mov	eax, cr0
	or	eax, 0x80010000	# CR0_PAGING = 1 << 31, CR0_WP = 1<<16
	mov	cr0, eax
	ret

paging_disable:
	mov	eax, cr0
	and	eax, ~0x80010000
	mov	cr0, eax

	xor	eax, eax
	mov	cr3, eax
	ret

##############################################################################
paging_print_pd$:
	pushad
	GDT_GET_BASE ebx, ds
	mov	esi, [page_directory]
	mov	ecx, 1024

0:	lodsd
	or	eax, eax
	jz	1f
	mov	edx, 1024
	sub	edx, ecx
	call	printhex4
	call	printspace
	shl	edx, 22
	call	printhex8
	printchar '-'
	add	edx, 1<<22
	call	printhex8
	call	printspace
	mov	edx, eax
	call	printhex8
.if 0 # causes PF..
	sub	edx, ebx
	and	edx, ~((1<<12)-1)
	DEBUG_DWORD edx
	mov	edx, [edx]
	call printspace
	call printhex8
.endif
	call	newline
1:	loop	0b
	popad
	ret
#####################



# Maps the given page in the given paging structure with PTE_FLAGs R, U and P
# in: esi = page directory physical address
# in: eax = page physical address
paging_idmap_page:
	test	eax, (1<<12)-1
	jnz	9f

	push	eax
	or	eax, PTE_FLAG_RW | PTE_FLAG_P
	jmp	1f

9:	printc 4, "page not page-aligned!"
	int	3
	stc
	ret
# KEEP-WITH-NEXT (1f)

# Maps the given page using the given flags in the given paging structure.
# NOTE that at least PTE_FLAG_P must be present for the page to be active.
#
# in: esi = page directory physical address, low 12 bit flags honored.
# in: eax = page physical address
paging_idmap_page_f:
	push	eax
1:	push_	ecx edx esi ebx
		mov	edx, cr3
		push	edx
		mov	edx, [page_directory_phys]
		mov	cr3, edx
	GDT_GET_BASE edx, ds
	# TODO: instruction pipelining

	mov	ecx, eax
	shr	ecx, 22	# divide by 4mb for PD index

	sub	esi, edx
	mov	esi, [esi + ecx * 4]	# get PT ptr
	and	esi, 0xfffff000
	jz	9f

	mov	ecx, eax
	sub	esi, edx
	and	ecx, ((1<<22)-1)	# modulo 4Mb
	shr	ecx, 12			# page index

	mov	[esi + ecx * 4], eax

0:		pop	edx
		mov	cr3, edx
	pop_	ebx esi edx ecx
	pop	eax
	invlpg	[eax]
	ret

9:	printc 4, "ERROR: No PT for PDE # "
	mov	edx, ecx
	call	printdec32
	print " ("
	call	printhex4
	print ") PD: "
	mov	edx, [esp + 4]
	call	printhex8
	mov	edx, eax
	mov	edx, [esp + 4 * 5]
	call	debug_printsymbol
	int 3
	jmp	0b

# in: esi = page directory phys
# in: eax = start of memory range
# in: ecx = size of memory range
paging_idmap_memrange:
	push_	eax ecx
	add	ecx, (1<<12) - 1	# round up
	shr	ecx, 12			# 4kb increments
	jz	9f

0:	call	paging_idmap_page_pt_alloc
	add	eax, 4096
	loop	0b

0:	pop_	ecx eax
	ret
9:	printlnc 4, "paging_idmap_memrange: zero size"
	jmp	0b


# Allocates a new page, identity-maps it, and clears it.
# When there is no page table for the memory region to map the page,
# it will use the new page as the page table for the region it is in,
# and will then recurse.
#
# in: esi = physical PD address
# out: eax = physical page address
paging_alloc_page_idmap:
	push_	edx ebx edi ecx

	call	malloc_page_phys
	jc	9f

	# calc PDE for this page and see if there is a PT
	GDT_GET_BASE ebx, ds
	mov	ecx, eax
	shr	ecx, 22
	sub	esi, ebx
	mov	edi, [esi + ecx * 4]	# get PDE
	add	esi, ebx
	and	edi, 0xfffff000
	# TODO: PDE_FLAG_S testing for 4Mb mapping (not used anymore)
	jnz	1f	# we have a page table, so paging_idmap_page will work.

	# it is empty. The 4mb region in which the allocate page
	# resides is not mapped.
	# Use this page to map that region, as it is the first page
	# allocated within that region.
	lea	edx, [eax + PDE_FLAG_RW | PDE_FLAG_P]

	# WARNING!
	#
	# the page is added to the PD as a page table, below, but, it is not
	# writable yet, and thus may contain bogus data corrupting the paging
	# structure.
	# Memory pages that have been freed (see schedule.s and mem.s), and
	# thus are likely to contain non-zero data, are almost certainly
	# guaranteed to be mapped already. This means that their 4Mb region is
	# already managed by a page table, and thus that page would not be
	# considered by this code to be used as a page table for it's region.
	# However, it is possible under the following assumptions:
	#   1) a page is allocated using malloc_page_phys, that is part of a
	#      new unmapped 4Mb region.
	#   2) Unused memory is (depending on hardware) zeroed on boot.
	#   3) the page can only be written if it is first mapped.
	#   4) the page has been written to because it's 4Mb region is mapped
	#      with PDE_FLAG_S (a 4Mb page without page table).
	#
	# Generally there will be no issue: when an unmapped page is allocated,
	# it will most likely come from a new and unused 4Mb range, which is
	# zeroed by hardware.
	#
	# Nonetheless, a simple precaution can be taken:
	# 1) Interrupts are disabled, so that no code will accidentally access
	#    a memory region in the 4Mb range.
	# 2) the page is marked as a page table.
	# 3) the entry in the page is updated to refer to itself, thus identity
	#    mapping the page.
	# 4) all other entries are zeroed.
	#
	# A question - how is it possible to write into the page before it is
	# identity mapped? It shouldn't be. This code then will only work
	# before paging is enabled.

	# clear the page - we don't want to trash the PD.
	# TODO: this will fail when paging is enabled, but,
	# so will the call to paging_idmap_page.

# XXX Unfortunately this does not work
#pushf
#cli
#call paging_disable
	push_ edi ecx
	push	eax
	mov	edi, eax
	sub	edi, ebx
	xor	eax, eax
	mov	ecx, 1024
	rep	stosd	# IF this generates page fault, surround disable PG
	pop	eax
	pop_ ecx edi
#call paging_enable
#popf

	# map in PDE as page table (PT)
	sub	esi, ebx
	mov	[esi + ecx * 4], edx
	add	esi, ebx
	# now we identity map the page, which should succeed:
	call	paging_idmap_page	# writes to the PTE in the PT!

	# Now we still need to allocate a free page.
	# We'll just recurse. There are 2 possibilities:
	# 1) the newly allocated page will be in the same 4Mb region
	# 2) it will not be.
	# In case 2), it will recurse again. It is higly unlikely that
	# this third recursion will yield yet another 4Mb region,
	# since pages are allocated contiguously at end-of-memory,
	# which will span a 4Mb boundary at most once. If there are
	# 4Mb pages allocated and a new one will cross the boundary,
	# the higher pages will already have been mapped.
	call	paging_alloc_page_idmap
	jc	9f
	# allright, we have a free page - map it.

1:	call	paging_idmap_page

	# now that the page is writeable, clear it.
	push	eax
	mov	edi, eax
	sub	edi, ebx
	xor	eax, eax
	mov	ecx, 1024
	rep	stosd
	pop	eax

	clc
0:	pop_	ecx edi ebx edx
	ret

9:	printlnc 4, "paging_alloc_page_idmap: cannot allocate page"
	stc
	int 3
	jmp	0b


# This method identity maps the given page, and allocates a page table
# for that, if necessary.
#
# in: esi = page dir phys
# in: eax = page phys
paging_idmap_page_pt_alloc:
	push_	edx ebx edi ecx

	GDT_GET_BASE ebx, ds

	# calc PD for this page
	mov	ecx, eax
	shr	ecx, 22
	sub	esi, ebx
	mov	edi, [esi + ecx * 4]	# get PDE
	add	esi, ebx
	and	edi, 0xfffff000
	jnz	1f		# we have a page table, proceed with idmap.

	# Allocate a page table to map the page.
	mov	edx, eax	# backup the original page to map

	call	paging_alloc_page_idmap
	jc	9f	# error message already printed
	# eax = fresh mapped page that we'll use as a page table.
	mov	edi, eax

	# register the fresh page as a page table in the page directory
	or	eax, PDE_FLAG_RW | PDE_FLAG_P
	sub	esi, ebx
	mov	[esi + ecx * 4], eax
	add	esi, ebx

	mov	eax, edx	# restore the argument page

1:	call	paging_idmap_page

	clc
9:	pop_	ecx edi ebx edx
	ret


############################################################################
# Paging structure printing functions

# Utility function: shared page directory loop, called from
# paging_show_usage and paging_show_struct.
#
# in: esi = page directory phys
# in: edi = pointer to a method to be called for each PDE
#            it's args: eax = PDE; ebx = ds-base
paging_print_$:
1:	print "Page Directory: "
	mov	edx, esi
	call	printhex8
	mov	edx, cr3
	print " CR3: "
	call	printhex8
	mov	edx, [page_directory_phys]
	print " (kernel PD: "
	call	printhex8
	println ")"

	GDT_GET_BASE ebx, ds
	sub	esi, ebx
	mov	ecx, 1024
0:	lodsd
	or	eax, eax	# print declared pages (FLAG_P not needed)
	jz	1f

	print	"PDE "
	mov	edx, 1024
	sub	edx, ecx
	call	printdec32
	call	printspace
	# print the 4mb physical memory range
	shl	edx, 22
	call	printhex8
	printchar '-'
	add	edx, 1 << 22
	call	printhex8
	# print the value
	mov	edx, eax
	print	" PT "
	call	printhex8
	# print the 4kb range of the page
	print " ("
	and	edx, 0xfffff000
	call	printhex8
	printchar '-'
	add	edx, 1<<12
	call	printhex8
	sub	edx, 1<<12
	PRINTFLAG eax, PDE_FLAG_G, ") G",") ."
	PRINTFLAG eax, PDE_FLAG_S, "S","."
	PRINTFLAG eax, PDE_FLAG_A, "A","."
	PRINTFLAG eax, PDE_FLAG_D, "D","."
	PRINTFLAG eax, PDE_FLAG_W, "W","."
	PRINTFLAG eax, PDE_FLAG_U, "U","."
	PRINTFLAG eax, PDE_FLAG_RW, "rw","ro"
	PRINTFLAG eax, PDE_FLAG_P, "P ",". "
	call	newline

	mov	edx, 1024
	sub	edx, ecx
	shl	edx, 22	# 4mb range

	call	edi	# in: eax, ebx, edx

1:	dec	ecx
	jnz	0b
	ret

##############################
# Print the pages that have been accessed in a compressed form.

# in: esi = page-dir-phys
paging_show_usage_:
	pushad
	jmp	1f

paging_show_usage:
	pushad
	mov	esi, [page_directory_phys]
1:	mov	edi, offset paging_print_pt_usage$
	call	paging_print_$
	popad
	ret

# in: eax = PDE
# in: ebx = GDT base for DS
paging_print_pt_usage$:
	test	eax, PDE_FLAG_S
	jnz	9f	# skip: 4Mb page - no page directory

	push	ebp
	push	esi
	push	ecx
	push	edx
	push	eax
	mov	ebp, esp
	push	dword ptr 0	# [ebp - 4] prev
	push	dword ptr 0	# [ebp - 8] cur count
	push	dword ptr 0	# [ebp - 12] # accessed pages
	push	dword ptr 0	# [ebp - 16] # non-null (declared) pages
	push	dword ptr 0	# [ebp - 20] # dirty (written/modified) pages

	mov	ecx, 1024
	mov	esi, eax
	and	esi, 0xfffff000
	sub	esi, ebx	# make ds-relative

####	# Collect information on contiguous accessed pages
0:	lodsd
	# update declared count
	or	eax, eax
	jz	1f
	inc	dword ptr [ebp - 16]	# declared pages
1:	# update dirty count
	test	eax, PTE_FLAG_D
	jz	1f
	inc	dword ptr [ebp - 20]	# dirty pages
1:

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
	mov	[ebp - 4], eax
	mov	[ebp - 8], ecx

3:	loop	0b

####	# final entry check: if last PTE accessed, no printing was done.
	test	eax, PTE_FLAG_A
	jz	3f
	call	8f

######## done, print summary
3:	print "   #pages: declared: "
	mov	edx, [ebp - 16]
	call	printdec32
	print " accessed: "
	mov	edx, [ebp - 12]
	call	printdec32
	print " dirty: "
	mov	edx, [ebp - 20]
	call	printdec32
	call	newline

	mov	esp, ebp
	pop	eax
	pop	edx
	pop	ecx
	pop	esi
	pop	ebp
9:	ret
########
# nameless utility method to print the range of pages
# updates [ebp-12] - the nr of accessed pages.
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


########################################
# print the paging structure: all non-null PDE's and PTE's,
# except for the 0..4mb range

# in: esi
paging_show_struct_:
	pushad
	jmp	1f

paging_show_struct:
	pushad
	mov	esi, [page_directory_phys]
1:	mov	edi, offset paging_print_pt_struct$
	call	paging_print_$
	popad
	ret

# this method is user callable.
paging_show_task_struct:
	ENTER_CPL0
	cli
	mov	esi, cr3
	push	esi
	mov	eax, [page_directory_phys]
	mov	cr3, eax
	call	paging_show_struct_
	pop	eax
	mov	cr3, eax
	sti
	pop_	esi eax
	ret

# in: eax = PDE
# in: ebx = GDT base for DS
paging_print_pt_struct$:
	test	eax, PDE_FLAG_S
	jz	4f
	println "  4Mb page"
	ret	# skip PTE: it's a 4mb page

4:	cmp	ecx, 1024
	jnz	2f
	println "  Identity Mapped 0..4Mb"
	ret
2:

	push	eax	# PDE
	push	esi
	push	ecx
	push	edi
	push	edx	# 4mb base
	xor	edi, edi
	mov	ecx, 1024
	mov	esi, eax
	and	esi, 0xfffff000
	sub	esi, ebx
5:	lodsd
	or	eax, eax
	jz	6f
	inc	edi

	print "  @"
	lea	edx, [esi + ebx - 4]
	call	printhex8
	print "  PTE "
	mov	edx, 1024
	sub	edx, ecx
	call	printdec32
		print " ("
		shl	edx, 12
		add	edx, [esp] # 4mb base
		call	printhex8
		printchar '-'
		add	edx, 1<<12
		call	printhex8
		print ") "

	mov	edx, eax
	call	printhex8

	PRINTFLAG eax, PTE_FLAG_G, " G"," ."
	PRINTFLAG eax, PTE_FLAG_A, "A","."
	PRINTFLAG eax, PTE_FLAG_D, "D","."
	PRINTFLAG eax, PTE_FLAG_W, "W","."
	PRINTFLAG eax, PTE_FLAG_U, "U","."
	PRINTFLAG eax, PTE_FLAG_RW, "rw","ro"
	PRINTFLAG eax, PTE_FLAG_P, "P (",". ("

	and	edx, ~1023
	call	printhex8
	printchar '-'
	add	edx, 1<<12
	call	printhex8
	println ")"

6:	dec	ecx
	jnz	5b
	print "  Page Table: "
	mov	edx, edi
	call	printdec32
	println "/1024 entries"
	pop	edx
	pop	edi
	pop	ecx
	pop	esi
	pop	eax
	ret
##############################

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

