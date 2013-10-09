DEFINE = 0
.include "../../defines.s"
.include "../../export.h"	# kernel gdt SEL
.include "../../macros.s"
.include "../../print.s"
.include "../../debugger/export.s"
.include "kapi/export.h"	# requires as -I ../..
.include "../../lib/hash.s"	# OBJ_STRUCT_SIZE
.include "../../lib/mem_handle.s"
.include "../../oo.s"
.include "../../fs.s"
.include "../fs_oofs.s"
