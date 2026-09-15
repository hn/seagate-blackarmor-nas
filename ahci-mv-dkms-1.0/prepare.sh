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

# Debian may ship the fix in its own sources once it reaches 6.1.y and the
# other stable series.  Patching on top of that would make "patch --forward"
# fail and turn a merely redundant build into a build error, so check first.
if grep -q ahci_mv_irq_handler ahci.c; then
	echo "prepare.sh: these sources already contain the 88SE6121 fix" >&2
	echo "prepare.sh: building a redundant module - this package is no" >&2
	echo "prepare.sh: longer needed for kernel $kver and can be removed" >&2
else
	echo "prepare.sh: applying the 88SE6121 interrupt ordering fix"
	patch -p0 --forward --no-backup-if-mismatch < ahci-6121-irq-order.patch

	# Fail loudly rather than silently building an unpatched module.  The
	# last check matters: if fuzz moved the registration hunk elsewhere -
	# for instance inside an #ifdef - the strings would still be present
	# while the code is compiled out, and the module would be silently
	# ineffective.
	grep -q ahci_mv_irq_handler ahci.c
	grep -q 'board_id == board_ahci_mv' ahci.c
	grep -A3 'board_id == board_ahci_mv' ahci.c | grep -q "MCP65 revision A1"
fi

# Give the module a distinguishable version, in both cases.  With the same
# MODULE_VERSION as the kernel's own module, dkms skips the install - and
# because this package ships a single module, nothing is installed at all,
# which ends in "die 6 Installation aborted" rather than a clean skip.  Only
# BUILD_EXCLUSIVE gets the skip right (exit 77), and dkms.conf uses it.
# The bump also makes "modinfo ahci" and the dmesg banner show which module
# is running.  Deliberately not part of the patch: upstream carries no
# version bump.
sed -i '/^#define DRV_VERSION/{/-mv1/!s|"\([^"]*\)"|"\1-mv1"|}' ahci.c
grep -q '^#define DRV_VERSION.*-mv1"' ahci.c

echo "prepare.sh: ok"
