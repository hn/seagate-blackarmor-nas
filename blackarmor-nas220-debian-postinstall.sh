#!/bin/bash -e
#
# blackarmor-nas220-debian-postinstall.sh V1.00
#
# Install Debian GNU/Linux 9 Stretch to a Seagate Blackarmor NAS 220
#
# (C) 2018-2019 Hajo Noerenberg
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

MACHINE=$(tr -d '\0' </proc/device-tree/model)

if [ "$MACHINE" != "Seagate Blackarmor NAS220" ]; then
	echo "This script has to be executed on the Seagate Blackarmor NAS 220 only"
	exit 1
fi

apt-get --yes install flash-kernel u-boot-tools sharutils

if [ ! -d /usr/share/flash-kernel/db ]; then
	echo "Install flash-kernel package first!"
	exit 1
fi

if ! grep -q "Seagate Blackarmor NAS220" /usr/share/flash-kernel/db/*.db; then
cat <<EOF >/usr/share/flash-kernel/db/seagate-blackarmor-nas220.db
Machine: Seagate Blackarmor NAS220
Kernel-Flavors: kirkwood marvell
DTB-Id: kirkwood-blackarmor-nas220.dtb
DTB-Append: yes
Mtd-Kernel: uimage
Mtd-Initrd: rootfs
U-Boot-Kernel-Address: 0x00040000
U-Boot-Initrd-Address: 0x00800000
Required-Packages: u-boot-tools  
EOF
fi

uudecode <<EOF
begin-base64 644 /etc/fw_env.config
IyBDb25maWd1cmF0aW9uIGZpbGUgZm9yIGZ3XyhwcmludGVudi9zZXRlbnYp
IHV0aWxpdHkuCiMgVXAgdG8gdHdvIGVudHJpZXMgYXJlIHZhbGlkLCBpbiB0
aGlzIGNhc2UgdGhlIHJlZHVuZGFudAojIGVudmlyb25tZW50IHNlY3RvciBp
cyBhc3N1bWVkIHByZXNlbnQuCiMgTm90aWNlLCB0aGF0IHRoZSAiTnVtYmVy
IG9mIHNlY3RvcnMiIGlzIG5vdCByZXF1aXJlZCBvbiBOT1IgYW5kIFNQSS1k
YXRhZmxhc2guCiMgRnV0aGVybW9yZSwgaWYgdGhlIEZsYXNoIHNlY3RvciBz
aXplIGlzIG9taXR0ZWQsIHRoaXMgdmFsdWUgaXMgYXNzdW1lZCB0bwojIGJl
IHRoZSBzYW1lIGFzIHRoZSBFbnZpcm9ubWVudCBzaXplLCB3aGljaCBpcyB2
YWxpZCBmb3IgTk9SIGFuZCBTUEktZGF0YWZsYXNoCiMgRGV2aWNlIG9mZnNl
dCBtdXN0IGJlIHByZWZpeGVkIHdpdGggMHggdG8gYmUgcGFyc2VkIGFzIGEg
aGV4YWRlY2ltYWwgdmFsdWUuCgojIE1URCBkZXZpY2UgbmFtZQlEZXZpY2Ug
b2Zmc2V0CUVudi4gc2l6ZQlGbGFzaCBzZWN0b3Igc2l6ZQlOdW1iZXIgb2Yg
c2VjdG9ycwovZGV2L210ZDEJCTB4MAkJMHgxMDAwMAoK
====
EOF

apt-get --yes install linux-image-marvell

grep -q 862013 /etc/fstab || echo -e "# Set /run size, see Debian Bug #862013\ntmpfs\t/run\ttmpfs\tnosuid,noexec,size=20M\t0\t0" >> /etc/fstab

