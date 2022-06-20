#!/bin/bash -e
#
# blackarmor-nas-debian-prep.sh
#
# Install Debian GNU/Linux to a Seagate Blackarmor NAS 110 / 220 / 440
#
# (C) 2018-2022 Hajo Noerenberg
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

RAWREPO=https://raw.githubusercontent.com/hn/seagate-blackarmor-nas/master
UBOOT=u-boot-2022.04
REBUILD=false

while [ $# -gt 0 ]; do
	case "$1" in
	--rebuild)
		REBUILD=true
		;;
	--force)
		FORCE=true
		;;
	--dist=*)
		DEBDIST=$(echo "$1" | cut -d= -f2)
		;;
	nas110)
		echo -e "\nUse the 'nas220' option, as the Blackarmor NAS 220 and 110 are reasonably compatible.\n"
		exit 0
		;;
	nas220)
		NASMODEL=$1
		# Installing Debian 11 (bullseye) and higher with 128MB RAM is a bit more complex,
		# check the website for more information.
		DEBDIST=${DEBDIST:-buster}
		;;
	nas440)
		NASMODEL=$1
		DEBDIST=${DEBDIST:-bullseye}
		echo -ne "\nWARNING: Support for the NAS 440 is currently experimental! "
		echo -ne "Hard disk slots 1 and 2 do NOT work with the current Linux kernel. "
		echo -e "Use '--force' to override this warning.\n"
		if [ -z "$FORCE" ]; then
			exit 1
		fi
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

if ! command -v mkimage &>/dev/null; then
	echo "'mkimage' missing, install 'u-boot-tools' package first"
	exit 1
fi

test -n "$NOVERBOSE" || VERBOSE="-v"

MIRRORLIST="https://archive.debian.org https://deb.debian.org"    # archive.d.o has to be the first
for CHKMIRROR in $MIRRORLIST; do
	DEBMIRROR=$CHKMIRROR/debian/dists/$DEBDIST/main/installer-armel/current/images/kirkwood
	KERNELVER=$(wget $WGETOPTS -qO- $DEBMIRROR/netboot/ | sed -n 's/.*vmlinu[xz]-\([^\t ]*\)-marvell.*/\1/p')
	if [ -n "${KERNELVER}" ]; then
		break
	fi
done
if [ -z "${KERNELVER}" ]; then
	echo "Unable to find Debian mirror for dist '$DEBDIST'. Either the mirror is broken or the dist does not exist for this arch."
	exit 1
fi

echo "NAS model set to: $NASMODEL"
echo "Using Debian dist '$DEBDIST' with Debian kernel version '$KERNELVER' for installation."

if [ -z "$NOPREPDIR" ]; then
	PREPDIR=blackarmor-$NASMODEL-debian
	test -d $PREPDIR || mkdir $VERBOSE $PREPDIR
	cd $PREPDIR
fi

rm $VERBOSE -f uImage-dtb uInitrd

if $REBUILD; then
	test -x /usr/bin/arm-none-eabi-gcc || apt-get install gcc-arm-none-eabi
	export CROSS_COMPILE=arm-none-eabi-
	export ARCH=arm

	wget $WGETOPTS -nc ftp://ftp.denx.de/pub/u-boot/$UBOOT.tar.bz2
	wget $WGETOPTS -nc $RAWREPO/$UBOOT-$NASMODEL.diff
	test -d $UBOOT || tar xjf $UBOOT.tar.bz2

	cd $UBOOT
	grep CONFIG_CMD_SATA configs/${NASMODEL}_defconfig &>/dev/null || patch -N -p1 < ../$UBOOT-$NASMODEL.diff
	make ${NASMODEL}_defconfig
	make -j2
	./tools/mkimage -n ./board/Seagate/$NASMODEL/kwbimage.cfg -T kwbimage -a 0x00600000 -e 0x00600000 -d u-boot.bin ../u-boot-$NASMODEL.kwb
	cp -v u-boot.dtb ../kirkwood-blackarmor-$NASMODEL.dtb
	cd ..

else
	wget $WGETOPTS -nc $RAWREPO/u-boot-$NASMODEL.kwb
	wget $WGETOPTS -nc $RAWREPO/kirkwood-blackarmor-$NASMODEL.dtb
fi

if [ -f u-boot-env.txt ]; then
	mkenvimage -p 0 -s 65536 -o u-boot-env.bin u-boot-env.txt
else
	wget $WGETOPTS -nc $RAWREPO/u-boot-env.bin
fi

wget $WGETOPTS -nc $DEBMIRROR/netboot/initrd.gz
wget $WGETOPTS -nc $DEBMIRROR/netboot/vmlinuz-$KERNELVER-marvell

echo

cat vmlinuz-$KERNELVER-marvell kirkwood-blackarmor-$NASMODEL.dtb > vmlinuz-$KERNELVER-marvell-kirkwood-blackarmor-$NASMODEL-dtb

mkimage -A arm -O linux -T kernel -C none -a 0x40000 -e 0x40000 \
	-n "Linux-$KERNELVER + $NASMODEL.dtb" \
	-d vmlinuz-$KERNELVER-marvell-kirkwood-blackarmor-$NASMODEL-dtb uImage-dtb

echo

if [ -f preseed.cfg ]; then
	gzip -d -c initrd.gz > initrd-preseed
	echo preseed.cfg | cpio -H newc -o -A -F initrd-preseed
	rm -f initrd-preseed.gz
	gzip -9 initrd-preseed

	mkimage -A arm -O linux -T ramdisk -C none \
		-n "Debian $DEBDIST netboot initrd+p" -d initrd-preseed.gz uInitrd
else
	mkimage -A arm -O linux -T ramdisk -C none \
		-n "Debian $DEBDIST netboot initrd" -d initrd.gz uInitrd
fi

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

