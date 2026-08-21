#!/bin/sh
# DKMS PRE_BUILD: extract ahci.c and ahci.h from Debian's own kernel source
# package for the kernel being built, then apply the 88SE6121 fix.
#
# Using Debian's sources means the private header drivers/ata/ahci.h is
# byte-identical to the one the running libahci.ko was built against, so only
# ahci.ko has to be replaced and there is no ABI guesswork.
set -e

kver=${1:?kernel version missing}
base=$(echo "$kver" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
top="linux-source-$base"
tarball="/usr/src/$top.tar.xz"

if [ ! -f "$tarball" ]; then
	echo "prepare.sh: $tarball not found - install linux-source (or linux-source-$base)" >&2
	exit 1
fi

# Warn if the source package and the headers package are not the same build.
src_ver=$(dpkg-query -W -f='${Version}' "linux-source-$base" 2>/dev/null || true)
hdr_ver=$(dpkg-query -W -f='${Version}' "linux-headers-$kver" 2>/dev/null || true)
if [ -n "$src_ver" ] && [ -n "$hdr_ver" ] && [ "$src_ver" != "$hdr_ver" ]; then
	echo "prepare.sh: WARNING linux-source ($src_ver) and linux-headers ($hdr_ver) differ" >&2
	echo "prepare.sh:          keep them at the same version to be safe" >&2
fi

echo "prepare.sh: extracting drivers/ata/{ahci.c,ahci.h} from $tarball"
tar -xJf "$tarball" --strip-components=3 --wildcards \
	"$top/drivers/ata/ahci.c" "$top/drivers/ata/ahci.h"

echo "prepare.sh: applying the 88SE6121 interrupt ordering fix"
patch -p0 --forward --no-backup-if-mismatch < ahci-6121-irq-order.patch

# Give the module a distinguishable version.  DKMS refuses to install a module
# whose MODULE_VERSION matches the one already in the kernel, and this also makes
# "modinfo ahci" and the dmesg banner show which module is actually running.
# Deliberately not part of the patch: upstream must not carry a version bump.
sed -i '/^#define DRV_VERSION/{/-mv1/!s|"\([^"]*\)"|"\1-mv1"|}' ahci.c
grep -q '^#define DRV_VERSION.*-mv1"' ahci.c

# Fail loudly rather than silently building an unpatched module.  The last
# check matters: if fuzz moved the registration hunk elsewhere - for instance
# inside an #ifdef - the strings would still be present while the code is
# compiled out, and the module would be silently ineffective.
grep -q ahci_mv_irq_handler ahci.c
grep -q 'board_id == board_ahci_mv' ahci.c
grep -A3 'board_id == board_ahci_mv' ahci.c | grep -q "MCP65 revision A1"
echo "prepare.sh: ok"
