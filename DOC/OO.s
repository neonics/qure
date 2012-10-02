Object orientation

[earlier writings in various places to be inserted - hash.s, CallingConvention]

classes: .long class1, class2, class2

class1:
	# factory method and arguments
	.long instance_factory
	.long object_size
	# virtual methods
	.long virtual_method1
	..
	.long virtual_methodN
class2:
	likewise


object_factory:
	mov	eax, [classes + eax * 4]
	call	[eax + instance_factory]
	call	array_newentry
	ret


class1_instance_factory:
	mov	ecx, [eax + object_size]
	ret


or

object_factory:
	mov	eax, [classes + eax * 4]
	mov	ecx, [eax + object_size]
	call	[eax + instance_factory]
	ret

instance_factory:
	call	array_newentry
	ret



##########################################################################
.struct 0
class_object_size: .long 0
class_newinstance: .long 0
##################################################
.text
dev_newinstance:
	mov	eax, [device_classes + eax * 4]
	call	[eax + class_newinstance]
	ret

class_newinstance:
##################################################
.data
device_classes:	.long dev_class_default, dev_class_pci, dev_class_ata
NUM_DEVICE_CLASSES = ( . = device_classes ) / 4
##################################################
# some object
.struct 0
object_size:	.long 0
object_class:	.long 0	# [object_classarray] + [object_class_id]
object_classarray:	.long 0	# pointer to the class array
object_class_id:	.long 0	# index into the class array
OBJECT_SIZE = .
.text

#########################################
.struct OBJECT_STRUCT_SIZE
dev_irq: 	.byte 0
dev_api_print:	.byte 0
DEV_OBJECT_SIZE = .
########################################
.data
dev_class_default:
	.long DEV_OBJECT_SIZE
	.long dev_default_constructor
	.long
	.long dev_default_print
.text
dev_default_constructor:
dev_default_print:
	ret

########################################
.struct DEV_OBJECT_SIZE
dev_pci_addr:	.word 0
DEV_PCI_OBJECT_SIZE = .
.data
dev_class_pci:
	.long DEV_PCI_OBJECT_SIZE
	.long dev_pci_constructor
	.long dev_pci_print
.text

dev_pci_constructor:
	ret
dev_pci_print:
	....
	ret
