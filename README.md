# seagate-blackarmor-nas

## Preamble
Some years ago [I reverse engineered](seagate-blackarmor-nas.txt) the Seagate Blackarmor NAS 220 and found a convenient way on [how to enable SSH on the device](sg2000-2000.1337.sp42.img). Later, the same mechanism was used to install an [alternative Linux firmware (Debian 5 Lenny)](custom-sg2000-2000.1337.sp99.img). Obviously, Debian 5 Lenny has reached end of life and should not be used in production anymore. 

## Debian 10 Buster

Evgeni Dobrev created a [kernel patch to include hardware support for the Blackarmor 220 in the mainline linux kernel](https://lore.kernel.org/patchwork/patch/529020/) and Moritz Rosenthal has released detailed docs on [how to update the system with an up-to-date linux kernel and Debian distribution](http://wiki.ccc-ffm.de/projekte:diverses:seagate_blackarmor_nas_220_debian). I used their work to create some (hopefully) helpful scripts which streamline the process a little further.

With the following instructions you'll manage to install a fully updateable Debian 10 Buster system to the NAS (kernel and initrd stored in NAND flash, updated via [flash-kernel package](https://packages.debian.org/stable/flash-kernel)).

(It's still possible to install Debian 9 Stretch by changing `DEBDIST=buster` to `DEBDIST=stretch` in `blackarmor-nas220-debian-prep.sh`)

### Warning

This completely removes the Seagate firmware and bootloader -- and there is no easy way of going back. There is a risk of bricking your device, especially if the u-boot bootloader does not start. You have been warned.

### Hardware

#### NAS 110

Quick specs: 800 Mhz CPU (Marvell 88F6192), 128MB RAM, 1 USB port, 1 network interface, max 1 drive. Motherboard
codename 'Mono'.

User [luctrev](https://github.com/luctrev) reports [a successful installation on his NAS 110](https://github.com/hn/seagate-blackarmor-nas/issues/6), so the hardware of the NAS 110 and 220 seems to be reasonable compatible.

#### NAS 220

Quick specs: 800 Mhz CPU (Marvell 88F6192), 128MB RAM, 2 USB ports, 1 network interface, max 2 drives. Motherboard
codename '[Lassen](https://en.wikipedia.org/wiki/Lassen_Peak)'.

This script has been developed and tested on the Blackarmor NAS 220. There
haven't been any error reports for a long time, so I consider the system as
stable.

#### NAS 400 / 420 / 440

Quick specs: 1.2 Ghz CPU (Marvell 88F6281), 256MB RAM, 3 USB ports, 2 network interfaces, max 4 drives. Motherboard
codename '[Shasta](https://en.wikipedia.org/wiki/Mount_Shasta)'.


All the NAS 4XX series products have the same 4-bay enclosure. The second digit in this number scheme refers to the
number of drives that ship with the device: no drives (NAS 400), 2 drives RAID 1 (NAS 420) and 4 drives RAID 5 (NAS 440).

Drives 3 and 4 are connected to the 88F6281 SoC, drives 1 and 2 are connected to a 88SE6121, which is connected via PCIe.

The NAS 4XX is [NOT compatible with Evgenis Kernel patch](https://github.com/hn/seagate-blackarmor-nas/issues/5) and therefore
this script does not work, do NOT try to install on a NAS 440, this will brick your device!
Thankfully, [Andreas Fischer](https://github.com/bantu) did [very some promising work](https://gist.github.com/bantu/d456865b91be6c99320b)
on providing an [U-Boot](https://github.com/bantu/u-boot/compare/master...sg-ba-440) and
[kernel patch](https://github.com/bantu/linux/compare/master...kw-ba-400-dts). Make sure to check his pages and help to finalize
the patches.

### Prerequisites

Setup a serial terminal (`115200 baud 8N1` e.g. by using `sudo screen /dev/ttyUSB0 115200`) by connecting a 3.3V serial cable like this:

![Blackarmor NAS220 serial port](https://github.com/hn/seagate-blackarmor-nas/blob/master/blackarmor-nas220-debian-serialport.jpg "NAS 220 serial port")
![Blackarmor NAS440 serial port](https://github.com/hn/seagate-blackarmor-nas/blob/master/blackarmor-nas440-debian-serialport.jpg "NAS 440 serial port")

### Preparing kernel and initrd images

Use your favourite Linux workstation to execute [`blackarmor-nas220-debian-prep.sh`](https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/blackarmor-nas220-debian-prep.sh) to download and prepare Das U-Boot bootloader and kernel image:

```
$ ./blackarmor-nas220-debian-prep.sh 
Using kernel 4.9.0-8 for installation.
mkdir: created directory 'blackarmor-nas220-debian'
URL:https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/u-boot-nas220.kwb [553356/553356] -> "u-boot-nas220.kwb" [1]
URL:https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/u-boot-env.bin [65536/65536] -> "u-boot-env.bin" [1]
URL:https://cdn-fastly.deb.debian.org/debian/dists/stretch/main/installer-armel/current/images/kirkwood/netboot/initrd.gz [11703715/11703715] -> "initrd.gz" [1]
URL:https://cdn-fastly.deb.debian.org/debian/dists/stretch/main/installer-armel/current/images/kirkwood/netboot/vmlinuz-4.9.0-8-marvell [2056160/2056160] -> "vmlinuz-4.9.0-8-marvell" [1]
URL:https://cdn-fastly.deb.debian.org/debian/dists/stretch/main/installer-armel/current/images/kirkwood/device-tree/kirkwood-blackarmor-nas220.dtb [10756/10756] -> "kirkwood-blackarmor-nas220.dtb" [1]

Image Name:   Linux-4.9.0-8 + nas220.dtb
Image Type:   ARM Linux Kernel Image (uncompressed)
Data Size:    2066916 Bytes = 2018.47 kB = 1.97 MB
Load Address: 00040000
Entry Point:  00040000

Image Name:   Debian stretch netboot initrd
Image Type:   ARM Linux RAMDisk Image (uncompressed)
Data Size:    11703715 Bytes = 11429.41 kB = 11.16 MB
Load Address: 00000000
Entry Point:  00000000

u-boot-nas220.kwb file size (512-byte aligned): 0x87200
u-boot-env.bin file size (512-byte aligned): 0x10000

Execute the following commands on the Blackarmor NAS:

usb start
fatload usb 0:1 0x800000 u-boot-nas220.kwb
nand erase 0x0 0x87200
nand write 0x800000 0x0 0x87200
fatload usb 0:1 0x800000 u-boot-env.bin
nand erase 0xA0000 0x10000
nand write 0x800000 0xA0000 0x10000
```

Copy the files `u-boot-nas220.kwb`, `u-boot-env.bin`, `uImage-dtb` and `uInitrd` from directory `blackarmor-nas220-debian` to a FAT formatted USB stick. Carefully examine the flash commands shown at the end of the script output.

### Flashing Das U-Boot bootloader

This step is only necessary for the very first installation or if you're upgrading from Debian 9 Stretch to Debian 10 Buster. If you're updating within the same Debian release or re-installing, directly skip to [Starting Debian installation](#Starting-Debian-installation).

Use the serial terminal to stop the Seagate boot process and to show the ethernet MAC address:

```
         __  __                      _ _
        |  \/  | __ _ _ ____   _____| | |
        | |\/| |/ _` | '__\ \ / / _ \ | |
        | |  | | (_| | |   \ V /  __/ | |
        |_|  |_|\__,_|_|    \_/ \___|_|_|
 _   _     ____              _
| | | |   | __ )  ___   ___ | |_
| | | |___|  _ \ / _ \ / _ \| __|
| |_| |___| |_) | (_) | (_) | |_
 \___/    |____/ \___/ \___/ \__|  ** uboot_ver:v0.1.7 **

 ** MARVELL BOARD: LASSEN LE

U-Boot 1.1.4 (Aug 17 2009 - 10:16:51) Marvell version: 3.4.14
U-Boot code: 00600000 -> 0067FFF0  BSS: -> 006CDE60

Soc: 88F6192 A0 (DDR2)
CPU running @ 800Mhz L2 running @ 400Mhz
SysClock = 200Mhz , TClock = 166Mhz

DRAM CAS Latency = 3 tRP = 3 tRAS = 8 tRCD=3
DRAM CS[0] base 0x00000000   size 128MB
DRAM Total size 128MB  16bit width
Found ADT7473, program PWM1 ... OK
Addresses 8M - 0M are saved for the U-Boot usage.
Mem malloc Initialization (8M - 7M): Done
NAND:32 MB

Marvell Serial ATA Adapter
Integrated Sata device found

CPU : Marvell Feroceon (Rev 1)
Scanning partition header:
Found sign PrEr at c0000
Found sign KrNl at 2c0000
Found sign RoOt at 540000

Streaming disabled
Write allocate disabled

USB 0: host mode
PEX 0: interface detected no Link.
Net:   egiga0 [PRIME]
Hit any key to stop autoboot:  0
Marvell>>
Marvell>> printenv ethaddr
ethaddr=00:10:75:42:42:42
```

Write down the MAC adress, you'll need it later. Connect the USB stick to port 1 of the NAS and flash the new bootloader (enter `usb start ... nand write` commands exactly as shown during preparation phase):

```
Marvell>> usb start
(Re)start USB...
USB:   scanning bus for devices... 3 USB Device(s) found
       scanning bus for storage devices... 1 Storage Device(s) found
Marvell>>
Marvell>> fatload usb 0:1 0x800000 u-boot-nas220.kwb
reading u-boot-nas220.kwb
.............................................................
553356 bytes read
Marvell>> nand erase 0x0 0x87200
NAND erase: device 0 offset 0x0, size 0x87200
Erasing at 0x84000 -- 100% complete.
OK
Marvell>> nand write 0x800000 0x0 0x87200
NAND write: device 0 offset 0x0, size 0x87200
 553472 bytes written: OK
Marvell>>
Marvell>> fatload usb 0:1 0x800000 u-boot-env.bin
reading u-boot-env.bin
.............
65532 bytes read
Marvell>> nand erase 0xA0000 0x10000
NAND erase: device 0 offset 0xA0000, size 0x10000
Erasing at 0x84000 -- 100% complete.
OK
Marvell>> nand write 0x800000 0xA0000 0x10000
NAND write: device 0 offset 0xA0000, size 0x10000
 65532 bytes written: OK
Marvell>>
Marvell>> reset
```

Make sure to restart the NAS via `reset` command after flashing the bootloader!

If your nas just restarts with the error message `cpu reset` after the `fatload usb 0:1 0x800000 u-boot-nas220.kwb` command try to format the usb stick to `ext2` and use `ext2load usb 0:1 ...` instead.

### Starting Debian installation

After resetting the NAS, connect a network cable to the NAS and execute `run bootcmd_usb` to start the Debian netboot installation:

```
U-Boot 2017.11 (Dec 18 2018 - 09:52:13 +0100)
NAS 220

SoC:   Kirkwood 88F6281_A0
DRAM:  128 MiB
WARNING: Caches not enabled
NAND:  32 MiB
In:    serial
Out:   serial
Err:   serial
Net:   egiga0
88E1116 Initialized on egiga0
IDE:   Bus 0: not available  Bus 1: not available
nas220>
nas220> run bootcmd_usb
starting USB...
USB0:   USB EHCI 1.00
scanning bus 0 for devices... 3 USB Device(s) found
       scanning usb for storage devices... 1 Storage Device(s) found
reading uImage-dtb
2066980 bytes read in 148 ms (13.3 MiB/s)
reading uInitrd
11703779 bytes read in 672 ms (16.6 MiB/s)
## Booting kernel from Legacy Image at 00040000 ...
   Image Name:   Linux-4.9.0-8+nas220-dtb
   Created:      2018-12-18  19:16:01 UTC
   Image Type:   ARM Linux Kernel Image (uncompressed)
   Data Size:    2066916 Bytes = 2 MiB
   Load Address: 00040000
   Entry Point:  00040000
   Verifying Checksum ... OK
## Loading init Ramdisk from Legacy Image at 00800000 ...
   Image Name:   netboot-initrd
   Created:      2018-12-19   9:26:51 UTC
   Image Type:   ARM Linux RAMDisk Image (uncompressed)
   Data Size:    11703715 Bytes = 11.2 MiB
   Load Address: 00000000
   Entry Point:  00000000
   Verifying Checksum ... OK
   Loading Kernel Image ... OK
   Loading Ramdisk to 07009000, end 07b325a3 ... OK

Starting kernel ...

Uncompressing Linux... done, booting the kernel.
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 4.9.0-8-marvell (debian-kernel@lists.debian.org) (gcc version 6.3.0 20170516 (Debian 6.3.0-18+deb9u1) ) #1 Debian 4.9.1
[    0.000000] CPU: Feroceon 88FR131 [56251311] revision 1 (ARMv5TE), cr=0005397f
[    0.000000] CPU: VIVT data cache, VIVT instruction cache
[    0.000000] OF: fdt:Machine model: Seagate Blackarmor NAS220
...
```

Proceed with Debian installation as usual (configure RAID, select packages, ...). Ignore the `No installable kernel was found` and `No boot loader installed` warnings (`Continue without installing a kernel?`=`Yes` and `Continue`), but do not reboot yet!

### Finishing Debian installation

Before rebooting the installation system (the `Installation complete` screen appears) select the `Go Back` button. Select `Execute a shell` (second last option in main menu) and chroot to the target system:

```
# mount -o bind /proc /target/proc
# mount -o bind /sys /target/sys
# chroot /target
# cd /tmp
```

Download and execute [`blackarmor-nas220-debian-postinstall.sh`](https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/blackarmor-nas220-debian-postinstall.sh) like this:

```
# wget https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/blackarmor-nas220-debian-postinstall.sh
# chmod +x blackarmor-nas220-debian-postinstall.sh
# ./blackarmor-nas220-debian-postinstall.sh
Reading package lists... Done 
Building dependency tree
Reading state information... Done
The following additional packages will be installed:
  busybox device-tree-compiler devio initramfs-tools initramfs-tools-core
  klibc-utils libklibc liblzo2-2 linux-base mtd-utils
Suggested packages:
  sharutils-doc bsd-mailx | mailx
The following NEW packages will be installed:
  busybox device-tree-compiler devio flash-kernel initramfs-tools
  initramfs-tools-core klibc-utils libklibc liblzo2-2 linux-base mtd-utils
  sharutils u-boot-tools
0 upgraded, 13 newly installed, 0 to remove and 0 not upgraded.
Need to get 1737 kB of archives. 
After this operation, 5340 kB of additional disk space will be used.
...
The following additional packages will be installed:
  firmware-linux-free linux-image-4.9.0-8-marvell
Suggested packages:                          
  linux-doc-4.9 debian-kernel-handbook
The following NEW packages will be installed:
  firmware-linux-free linux-image-4.9.0-8-marvell linux-image-marvell
0 upgraded, 3 newly installed, 0 to remove and 0 not upgraded.
Need to get 22.0 MB of archives.
After this operation, 91.3 MB of additional disk space will be used.
...
Preparing to unpack .../firmware-linux-free_3.4_all.deb ...
Unpacking firmware-linux-free (3.4) ...                   
Selecting previously unselected package linux-image-4.9.0-8-marvell.
Preparing to unpack .../linux-image-4.9.0-8-marvell_4.9.130-2_armel.deb ...
Unpacking linux-image-4.9.0-8-marvell (4.9.130-2) ...
...
Using DTB: kirkwood-blackarmor-nas220.dtb
Installing /usr/lib/linux-image-4.9.0-8-marvell/kirkwood-blackarmor-nas220.dtb into /boot/dtbs/4.9.0-8-marvell/kirkwood-blackarmor-nas220.dtb
Taking backup of kirkwood-blackarmor-nas220.dtb.
Installing new kirkwood-blackarmor-nas220.dtb.
flash-kernel: installing version 4.9.0-8-marvell   
flash-kernel: appending /usr/lib/linux-image-4.9.0-8-marvell/kirkwood-blackarmor-nas220.dtb to kernel
Generating kernel u-boot image... done.
Erasing 16 Kibl (using 2066980/5242880 bytes)...
...
Writing data to block 124 at offset 0x1f0000
Writing data to block 125 at offset 0x1f4000
Writing data to block 126 at offset 0x1f8000
done.
```

Set ethernet MAC address and enable autoboot (only needed after flashing Das U-Boot bootloader):

```
# fw_setenv ethaddr 00:10:75:42:42:42
# fw_setenv bootdelay 3
# exit
# exit
```

Exit the shell, remove USB stick and reboot the system via the Debian installer main menu. Don't forget the `Finish installation` item last or you won't be able to login later!

### Additional tuning

- As Moritz [suggests](http://wiki.ccc-ffm.de/projekte:diverses:seagate_blackarmor_nas_220_debian#tuning) it is advisable to install the `lm-sensors` and `hdparm` packages.

- He also notes that you can adjust the fan speed by echo-ing the desired speed to sysfs: `echo 128 > /sys/class/i2c-dev/i2c-0/device/0-002e/pwm1`.

