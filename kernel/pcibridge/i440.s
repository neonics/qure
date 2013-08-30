###############################################################################
# Intel 440 BX/ZX/DC Host Bridge
.intel_syntax noprefix
#
# 
#                 [CPU] [CPU]<--->[IO APIC]<--[PIIX4 PCI-to-ISA-bridge]
#                   ^     ^                         ^       ^       ^
#                   |     |                         |       |       |
#                 __v_____v___Host Bus(Front-Side)  v       v       | 
#                      ^                         [2x IDE] [2x USB]  |
#       ---------------|---------------------              _________v__ ISA Bus
#       |82443BX      _v_________________   |               ^
#       |Host Bridge |Host-To-PCI Bridge|<--+---            |__>[BIOS]
#       |            ----8086 7190-------   |  |
#       |                                   |  |
#       |    _______________________________|__v___ PCI Bus 0 (primary)
#       |      ^                            |
#       |      |                            |
#       |  ____v______________________      |
#       | |Virtual Host-To-PCI Bridge|      |       _____
#       | ---8086 7191----------------      |<---->| RAM |
#       |              ^                    |      -------
#       |              |                    |
#       ---------------+--------------------|
#        ______________|
#       |AGP GFX Device|<-- PCI Bus 1 - AGP 2x
#        --------------
#

# This controller is directly connected to the CPU and exports
# itself in the PCI configuration space as residing on bus 0, slot 0.
# It thus represents the access from the CPU to all PCI buses.
# 
# The controller further exports itself as a PCI-to-PCI bridge on bus 0 slot 1,
# bridging bus 0 to bus 1, which is connected to the Graphics processor.
#
# 
DECLARE_PCI_DRIVER BRIDGE, nulldev, 0x8086, 0x7190, "i440", "Intel 440BX/ZX/DC Host Bridge"
DECLARE_PCI_DRIVER BRIDGE_PCI2PCI,    nulldev, 0x8086, 0x7191, "i440agp", "Intel 440 AGP Bridge"
