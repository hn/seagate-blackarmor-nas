# DKMS package: 88SE6121 interrupt ordering fix for Debian kernels

Rebuilds `ahci.ko` with the fix in `ahci-6121-irq-order.patch` whenever
Debian installs a new kernel. The module lands in
`/lib/modules/<ver>/updates/`, which `depmod` prefers over the kernel's own
`kernel/drivers/ata/`.

## How the private header problem is solved

`drivers/ata/ahci.h` is a *private* header and is not part of
`linux-headers-*`, but `ahci.ko` and `libahci.ko` share `struct
ahci_host_priv` from it. Shipping a hand-copied `ahci.h` would risk an ABI
mismatch against Debian's own `libahci.ko`.

So the build takes the sources from Debian itself: `PRE_BUILD` runs
`prepare.sh`, which extracts just `drivers/ata/ahci.c` and
`drivers/ata/ahci.h` from `/usr/src/linux-source-<major.minor>.tar.xz` — the
exact tree Debian built its binary kernels from, Debian patches included — and
then applies the one-hunk fix. `ahci.h` is therefore byte-identical to the one
`libahci.ko` was compiled against, and only `ahci.ko` has to be replaced.

`prepare.sh` fails loudly if the tarball is missing, if the patch does not
apply, or if the resulting `ahci.c` does not contain the fix. A failed DKMS
build is visible; a silently unpatched or ABI-mismatched module would not be.

## Build and install

The package is `Architecture: all` and compiles nothing at package build time —
the module is built by DKMS on the target when the package is installed. So it
can be built on any machine:

```sh
sudo apt install devscripts debhelper dkms        # build host
cd ahci-mv-dkms-1.0
dpkg-buildpackage -us -uc -b
```

On the NAS:

```sh
sudo apt install linux-headers-marvell linux-source
sudo apt install ../ahci-mv-dkms_1.0_all.deb
```

The postinst runs `dkms add/build/install`, which calls `prepare.sh`, extracts
`ahci.c` and `ahci.h` from `/usr/src/linux-source.tar.xz`, applies the
patch, builds `ahci.ko` into `/lib/modules/<ver>/updates/` and refreshes the
initramfs.

## Verify

```sh
dkms status                            # ahci-mv/1.0, <ver>, armv5tel: installed
modinfo ahci | head -3                 # filename must be under .../updates/
lsinitramfs /boot/initrd.img-$(uname -r) | grep -E 'ahci|libahci'
```

`ahci` is usually part of the initramfs, which is why `dkms.conf` sets
`REMAKE_INITRD="yes"`.

After a reboot, the SATA-2/3 disks on the 88SE6121 must come up without
`qc timeout`:

```sh
dmesg | grep -E 'ata[0-9]+.*(link up|ATA-|qc timeout)'
```

## On kernel upgrades

Trixie is the last Debian release for armel and stays on the 6.12 series, so
only point releases change. Those come from the same source package, and
`prepare.sh` picks up the matching sources automatically — nothing to do.

The patch has been seen to apply with exact context (line offsets only, no
fuzz) to 5.15 and to several 6.x series, so the package is not limited to
trixie. Note that applying cleanly is not the same as compiling: for a series
you have not built before, watch the first DKMS build.

Two things can still go wrong, and both are visible:

- **`linux-source` lags behind `linux-headers-*`.** `prepare.sh` warns
  when the two package versions differ; keep them upgraded together.
- **Debian changes `ahci.c` around the patch anchors.** Then `patch` fails and
  the DKMS build fails. Refresh the patch by hand — the fix is one moved
  statement (`writel(irq_stat, mmio + HOST_IRQ_STAT)` before
  `ahci_handle_port_intr()`, in a private handler selected for
  `board_ahci_mv`), so re-creating it is quick. The reasoning and the measured
  evidence are in <https://bugzilla.kernel.org/show_bug.cgi?id=216094>.

## Removal

```sh
sudo dkms remove -m ahci-mv -v 1.0 --all
sudo update-initramfs -u
```
