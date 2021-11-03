#!/bin/bash -e
#
# blackarmor-nas-debian-prep.sh
#
# Install Debian GNU/Linux to a Seagate Blackarmor NAS 110 / 220 / 440
#
# (C) 2018-2021 Hajo Noerenberg
#
#
# http://www.noerenberg.de/
# https://github.com/hn/seagate-blackarmor-nas
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3.0 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.txt>.
#

DEBDIST=bullseye
DEBMIRROR=https://deb.debian.org/debian/dists/$DEBDIST/main/installer-armel/current/images/kirkwood
UBOOT=u-boot-2017.11
REBUILD=false

while [ $# -gt 0 ]; do
	case "$1" in
	--rebuild)
		REBUILD=true
		;;
	nas110)
		echo -e "\nUse the 'nas220' option, as the Blackarmor NAS 220 and 110 are reasonably compatible.\n"
		exit 0
		;;
	nas220)
		NASMODEL=$1
		;;
	nas440)
		NASMODEL=$1
		echo -ne "\nWARNING: Support for the NAS 440 is currently alpha quality! "
		echo -ne "Things are incomplete, buggy and unstable. Do not install to your NAS if "
		echo -e "you plan to use it for anything useful.\n"
		exit 1
		;;
	*)
		echo "$0: unrecognized option: '$1'" >&2
		exit 1
		;;
	esac
	shift
done

if [ -z "$NASMODEL" ]; then
	echo "Usage: $0 [--rebuild] <nas110|nas220|nas440>"
	exit 1
fi

if [ ! -x /usr/bin/mkimage ]; then
	echo "'mkimage' missing, install 'u-boot-tools' package first"
	exit 1
fi

PREPDIR=blackarmor-$NASMODEL-debian
KERNELVER=$(wget -qO- $DEBMIRROR/netboot/ | sed -n 's/.*vmlinuz-\([^\t ]*\)-marvell.*/\1/p')

echo "NAS model set to: $NASMODEL"
echo "Using Debian dist '$DEBDIST' with Debian kernel version '$KERNELVER' for installation."

test -d $PREPDIR || mkdir -v $PREPDIR
cd $PREPDIR

rm -vf uImage-dtb uInitrd

if $REBUILD; then
	test -x /usr/bin/arm-none-eabi-gcc || apt-get install gcc-arm-none-eabi
	export CROSS_COMPILE=arm-none-eabi-
	export ARCH=arm

	# Das U-Boot bootloader
	wget -nc ftp://ftp.denx.de/pub/u-boot/$UBOOT.tar.bz2
	tar xjf $UBOOT.tar.bz2
	if [ $NASMODEL = "nas440" ]; then
		wget -nc https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/$UBOOT-$NASMODEL.diff
		patch -p0 < $UBOOT-$NASMODEL.diff
	fi
	cd $UBOOT
	make ${NASMODEL}_defconfig
	make -j2
	./tools/mkimage -n ./board/Seagate/$NASMODEL/kwbimage.cfg -T kwbimage -a 0x00600000 -e 0x00600000 -d u-boot.bin ../u-boot-$NASMODEL.kwb
	cd ..

	# Linux kernel DTB
	if [ $NASMODEL = "nas440" ]; then
		test -x /usr/bin/bison || apt-get install bison
		test -x /usr/bin/flex || apt-get install flex
		test -f /usr/include/openssl/bio.h || apt-get install libssl-dev

		LATESTDKL=$(curl -sI https://sources.debian.org/api/src/linux/$DEBDIST/ | grep -i Location)
		KV=$(echo "$LATESTDKL" | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
		echo "Debian dist '$DEBDIST' with Debian kernel version '$KERNELVER' is based on vanilla kernel '$KV'."
		KM=$(echo "$KV" | sed -n 's/^\([0-9]\+\)\..*/\1/p')
		wget -nc https://cdn.kernel.org/pub/linux/kernel/v${KM}.x/linux-$KV.tar.xz
		wget -nc https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/linux-$NASMODEL.diff
		# Extract minimal subset of kernel source, use full kernel source if you experience problems
		tar xvJf linux-$KV.tar.xz linux-$KV/Makefile linux-$KV/arch/arm/ linux-$KV/scripts/ linux-$KV/include/ linux-$KV/tools/
		tar xvJf linux-$KV.tar.xz --wildcards "linux-$KV/*Kconfig*"
		cd linux-$KV
		patch -p1 < ../linux-$NASMODEL.diff

		make defconfig
		make kirkwood-blackarmor-$NASMODEL.dtb

		mv -v ./arch/arm/boot/dts/kirkwood-blackarmor-$NASMODEL.dtb ../
		cd ..
	fi
else
	wget -nc https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/u-boot-$NASMODEL.kwb
	if [ $NASMODEL = "nas440" ]; then
		wget -nc https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/kirkwood-blackarmor-nas440.dtb
	fi
fi

if [ -f u-boot-env.txt ]; then
	mkenvimage -p 0 -s 65536 -o u-boot-env.bin u-boot-env.txt
else
	wget -nc https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master/u-boot-env.bin
fi

wget -nc $DEBMIRROR/netboot/initrd.gz
wget -nc $DEBMIRROR/netboot/vmlinuz-$KERNELVER-marvell
if [ $NASMODEL = "nas220" ]; then
	wget -nc $DEBMIRROR/device-tree/kirkwood-blackarmor-nas220.dtb
fi

echo

cat vmlinuz-$KERNELVER-marvell kirkwood-blackarmor-$NASMODEL.dtb > vmlinuz-$KERNELVER-marvell-kirkwood-blackarmor-$NASMODEL-dtb

mkimage -A arm -O linux -T kernel -C none -a 0x40000 -e 0x40000 \
	-n "Linux-$KERNELVER + $NASMODEL.dtb" \
	-d vmlinuz-$KERNELVER-marvell-kirkwood-blackarmor-$NASMODEL-dtb uImage-dtb

echo

mkimage -A arm -O linux -T ramdisk -C none \
	-n "Debian $DEBDIST netboot initrd" -d initrd.gz uInitrd

echo

UBOOTKWBASIZE=0x$(printf "%x" $((512 * $(($(($(stat -c "%s" u-boot-$NASMODEL.kwb) + 511)) / 512)))))
echo "u-boot-$NASMODEL.kwb file size (512-byte aligned): $UBOOTKWBASIZE"
UBOOTENVASIZE=0x$(printf "%x" $((512 * $(($(($(stat -c "%s" u-boot-env.bin) + 511)) / 512)))))
echo "u-boot-env.bin file size (512-byte aligned): $UBOOTENVASIZE"
echo
echo "Execute the following commands on the Blackarmor NAS:"
echo
echo "usb start"
echo "fatload usb 0:1 0x800000 u-boot-$NASMODEL.kwb"
echo "nand erase 0x0 $UBOOTKWBASIZE"
echo "nand write 0x800000 0x0 $UBOOTKWBASIZE"
echo "fatload usb 0:1 0x800000 u-boot-env.bin"
echo "nand erase 0xA0000 $UBOOTENVASIZE"
echo "nand write 0x800000 0xA0000 $UBOOTENVASIZE"

echo

