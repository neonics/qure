.macro .text16
	TEXTSUBSECTION = 0
	.text 0
	.code16
.endm

.macro .data16
	.text 1
.endm

.macro .text16end
	.text 2
	.code16
.endm

.macro .text32
	TEXTSUBSECTION = 3
	.text 3
	.code32
.endm

.macro .code16_
	CODEBITS = 16
	.code16
.endm

.macro .code32_
	CODEBITS = 32
	.code32
.endm

.macro .previous
	.if TEXTSUBSECTION == 0
		.text16
	.else
	.if TEXTSUBSECTION == 3
		.text32
	.else
	.error "Unknown text subsection"
	.print TEXTSUBSECTOIN
	.endif
	.endif
	
	.ifdef CODEBITS
	.if CODEBITS == 16
		.code16
	.else
	.if CODEBITS == 32
		.code32
	.endif
	.endif
	.endif
.endm
