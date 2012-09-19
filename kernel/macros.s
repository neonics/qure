.macro .text16
	#.section .text16, "x"
	.text 0
	.code16
.endm

.macro .data16
	#.section .text16, 1
	.text 1
.endm

.macro .text16end
	#.section .text16, 3
	.text 2
	.code16
.endm

.macro .text32
	.text 3
	.code32
.endm

