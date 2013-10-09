.ifdef RING2_INCLUDED
.else

.include "defines.s"
.include "macros.s"

.text32
.global code_ring2_inc_start
code_ring2_inc_start:
DEFINE=0
.include "debugger/export.s"
.include "print.s"
.include "oo.s"
.include "export.h"
.include "kapi/export.h"
.include "lib/hash.s"
#.include "pci.s"
.include "gdt.s"
.include "pic.s"
.include "mutex.s"

.include "fs.s"
.include "shell.s"
.include "schedule.s"	# for net service daemons
.include "dma.s"	# for sb
.include "pic.s"	# for PIC_ENABLE_IRQ (ata.s)

.include "keycodes.s"	# sb.s keyboard check

.global code_ring2_inc_end
code_ring2_inc_end:
.endif
DEFINE=1


#############################################
.data SECTION_DATA
data_ring2_start:; .global data_ring2_start
.data SECTION_DATA_STRINGS
data_ring2_strings_start:; .global data_ring2_strings_start
.data SECTION_DATA_PCI_DRIVERINFO
data_pci_driverinfo_start: # .word vendorId, deviceId
.data SECTION_DATA_BSS
data_ring2_bss_start:; .global data_ring2_bss_start
#############################################
include "dev.s" dev
include "pci.s", pci
include "ata.s", ata
include "partition.s", partition
include "fs.s", fs
include "fs/fat.s", fs_fat
include "fs/iso9660.s", fs_iso9660
include "fs/sfs.s", fs_sfs
include "fs/fs_oofs.s", fs_oofs


code_nic_start:
include "nic.s"
include "nic/rtl8139.s"
include "nic/i8254.s"
include "nic/am79c971.s"
code_nic_end:

include "net/net.s", net

code_vid_start:
include "vmware/svga2.s"
include "vbox/vbva.s"
code_vid_end:

code_usb_start:
include "usb/usb.s"
include "usb/usb_ohci.s"
code_usb_end:


code_southbridge_start:
include "pcibridge/i440.s"	# Intel i440 PCI Host Bridge
include "pcibridge/ipiix4.s"	# Intel PIIX4 ISA/IDE/USB/AGP Bridge
code_southbridge_end:

include "vbox/vbga.s", vbox
code_sound_start:
include "sound/es1371.s", es1371
include "sound/sb.s", sb
code_sound_end:



.ifdef RING2_INCLUDED
.else
############# exports
.global cmd_gfx
.global gfx_mode
.global cmd_svga

.global cmd_nic_list
.global cmd_ifconfig
.global cmd_ifup
.global cmd_ifdown
.global cmd_route
.global cmd_dhcp
.global cmd_host
.global cmd_traceroute
.global cmd_netstat
.global cmd_arp
.global cmd_ping
.global net_icmp_list

.global cmd_dnsd
.global cmd_httpd
.global cmd_smtpd
.global cmd_sshd
.global cmd_sipd

.global code_net_start
.global code_net_end
.global code_nic_start
	.global nic_zeroconf
.global code_nic_end
.global code_vid_start
.global code_vid_end
.global code_usb_start
.global code_usb_end
.global code_southbridge_start
.global code_southbridge_end
.global code_dev_start
	.global dev_api_constructor
	.global class_dev
	.global dev_name	# struct field
	.global cmd_dev
.global code_dev_end
.global code_ata_start
	.global ata_list_drives
	.global class_dev_ata
	.global dev_ata_device
	.global ata_print_size
	.global ata_read
	.global ata_write
	.global ata_drive_types
	.global ata_print_capacity
	.global atapi_read_capacity
	.global atapi_read12$
.global code_ata_end
.global code_partition_start
	.global disk_parse_partition_label
	.global disk_parse_label
	.global disk_print_label
	.global disk_get_partition
	.global cmd_disks_print$
	.global cmd_fdisk
	.global cmd_partinfo$
	.global PT_LBA_START
	.global PT_SECTORS
	.global PT_TYPE
.global code_partition_end
.global code_pci_start
	.global pci_list_drivers
	.global pci_list_devices
	.global pci_device_class_names
	.global PCI_MAX_KNOWN_DEVICE_CLASS
	.global pci_print_bus_architecture
	.global pci_list_obj_counters
	.global pci_busmaster_enable
	.global class_nulldev
	.global DEV_PCI_CLASS_BRIDGE
	.global DEV_PCI_CLASS_BRIDGE_ISA
	.global DEV_PCI_CLASS_BRIDGE_PCI2PCI
	.global DEV_PCI_CLASS_BRIDGE_PCI2PCI_STS
	.global DEV_PCI_CLASS_NIC_ETH
	.global DEV_PCI_CLASS_SERIAL_USB
	.global DEV_PCI_CLASS_SERIAL_USB_EHCI
	.global DEV_PCI_CLASS_SERIAL_USB_OHCI
	.global DEV_PCI_CLASS_STORAGE_IDE
	.global DEV_PCI_CLASS_VID_VGA
	.global pci_get_bar
	.global pci_get_bar_addr
	.global pci_get_device_subclass_info
	.global pci_read_config
	.global pci_write_config

.global code_pci_end
.global code_vbox_start
.global code_vbox_end
.global code_sound_start
	.global sound_set_samplerate
	.global sound_set_format
	.global sound_playback_init
	.global sound_playback_start
	.global sound_playback_stop
	# sb
	.global class_sb
	.global sb_dma_buf_half
	.global SB_StopPlay
	# es1371
	.global es1371_isr_dev$
.global code_sound_end

.global data_pci_driverinfo_start
.global data_pci_driverinfo_end

.endif

#############################################
.data SECTION_DATA_STRINGS -1
data_ring2_end:; .global data_ring2_end
.data SECTION_DATA_STRINGS
data_ring2_strings_end:; .global data_ring2_strings_end
.data SECTION_DATA_PCI_DRIVERINFO
data_pci_driverinfo_end:; 
.data SECTION_DATA_BSS
data_ring2_bss_end:; .global data_ring2_bss_end
#############################################
