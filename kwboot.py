#!/usr/bin/env python3
"""
Minimal kwboot for Marvell Kirkwood SoCs.
Sends the BootROM "magic" pattern over UART, then transfers a .kwb image
via Xmodem-128 with 8-bit checksum.

Usage:
    python3 kwboot.py <serial_port> <image.kwb> [--baud 115200]

Power-cycle (or reset) the NAS shortly after launching this script.
"""
import argparse, sys, time, struct

try:
    import serial
except ImportError:
    sys.exit("pyserial missing — run: pip3 install --user pyserial")

# Marvell BootROM constants
MAGIC_BOOT = bytes([0xBB, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])
SOH = 0x01
EOT = 0x04
ACK = 0x06
NAK = 0x15
CAN = 0x18
BLK_SIZE = 128
SENSE_INTERVAL = 0.010   # 10ms between magic pattern transmissions
SENSE_TIMEOUT  = 0.050   # 50ms wait for NAK reply each round
BLK_TIMEOUT    = 10.0    # seconds to wait for ACK/NAK on each block
MAX_BLK_RETRY  = 16

def sense_bootrom(ser):
    print("Sending boot pattern. Power-cycle / reset the NAS now…", flush=True)
    n = 0
    seen = bytearray()
    while True:
        ser.write(MAGIC_BOOT)
        ser.flush()
        time.sleep(SENSE_INTERVAL)
        ser.timeout = SENSE_TIMEOUT
        chunk = ser.read(64)
        n += 1
        if chunk:
            seen.extend(chunk)
            if NAK in chunk:
                print(f"\nBootROM detected (got NAK after {n} rounds). Starting transfer.", flush=True)
                return
            # show stray bytes for debugging
            print(f"  [round {n}] got {len(chunk)} bytes: {chunk!r}", flush=True)
        if n % 50 == 0:
            print(f"  [round {n}] no NAK yet (sent {n*len(MAGIC_BOOT)} pattern bytes, seen back {len(seen)})", flush=True)

def make_block(pnum, data):
    pkt = bytearray(132)
    pkt[0] = SOH
    pkt[1] = pnum & 0xFF
    pkt[2] = (~pnum) & 0xFF
    n = min(BLK_SIZE, len(data))
    pkt[3:3+n] = data[:n]
    csum = sum(data[:n]) & 0xFF
    pkt[131] = csum
    return bytes(pkt)

def send_image(ser, img):
    total = len(img)
    sent = 0
    pnum = 1
    blk_count = (total + BLK_SIZE - 1) // BLK_SIZE
    print(f"Image size: {total} bytes ({blk_count} blocks)")
    # Wait for BootROM to be ready to receive (original C kwboot does sleep(2))
    print("Settling 2s post-NAK…", flush=True)
    time.sleep(2)
    # Drain any stale bytes without toggling DTR/RTS
    ser.timeout = 0.05
    drained = bytearray()
    while True:
        d = ser.read(256)
        if not d:
            break
        drained.extend(d)
    print(f"  drained {len(drained)} bytes: {bytes(drained)!r}", flush=True)
    ser.timeout = BLK_TIMEOUT
    last_pct = -1
    start = time.time()
    for b in range(blk_count):
        chunk = img[b*BLK_SIZE:(b+1)*BLK_SIZE]
        if len(chunk) < BLK_SIZE:
            chunk = chunk + b'\x00' * (BLK_SIZE - len(chunk))
        pkt = make_block(pnum, chunk)
        for attempt in range(MAX_BLK_RETRY):
            ser.write(pkt)
            ser.flush()
            # read response, ignoring stray output
            t0 = time.time()
            resp = b''
            stray = bytearray()
            while time.time() - t0 < BLK_TIMEOUT:
                c = ser.read(1)
                if not c:
                    continue
                if c[0] in (ACK, NAK, CAN):
                    resp = c
                    break
                stray.append(c[0])
            if stray:
                print(f"\n  block {pnum} attempt {attempt+1}: stray bytes before response: {bytes(stray)!r}", flush=True)
            if not resp:
                raise SystemExit(f"\nTimeout waiting for ACK on block {pnum} (attempt {attempt+1})")
            if resp[0] == ACK:
                break
            if resp[0] == CAN:
                raise SystemExit(f"\nTarget cancelled at block {pnum}")
            print(f"\n  block {pnum} got NAK, retrying ({attempt+1}/{MAX_BLK_RETRY})", flush=True)
        else:
            raise SystemExit(f"\nToo many NAK retries on block {pnum}")
        sent += min(BLK_SIZE, total - b*BLK_SIZE)
        pct = sent * 100 // total
        if pct != last_pct:
            elapsed = time.time() - start
            rate = sent / elapsed / 1024 if elapsed > 0 else 0
            sys.stdout.write(f"\r {pct:3d}%  {sent}/{total} bytes  {rate:.1f} KB/s    ")
            sys.stdout.flush()
            last_pct = pct
        pnum = (pnum + 1) & 0xFF
        if pnum == 0:
            pnum = 1   # protocol wraps 255 -> 1 typically
    print("\nSending EOT…")
    # send EOT, expect ACK
    got_ack = False
    for _ in range(8):
        ser.write(bytes([EOT]))
        ser.flush()
        c = ser.read(1)
        if c and c[0] == ACK:
            print("Transfer complete (got final ACK).")
            got_ack = True
            break
    if not got_ack:
        print("Warning: no final ACK after EOT, but transfer should have landed.")
    print_unpatch_instructions(total)

ORIG_BLOCKID = None  # set by patch_uart_boot if we patched
ORIG_CSUM = None

def patch_uart_boot(img):
    """Patch kwbimage v0 header to indicate UART boot source.

    The BootROM in Marvell Kirkwood SoCs checks byte 0 of the image header
    (the "blockid" / boot source) and refuses to load images marked for
    NAND/SPI/etc when receiving via UART recovery. We rewrite byte 0 to
    0x69 (UART) and recompute the header checksum at offset 0x1F (which is
    the simple 8-bit sum of bytes 0..0x1E).

    Stashes the original blockid and checksum so we can print recovery
    commands to "unpatch" the header in RAM before flashing to NAND."""
    global ORIG_BLOCKID, ORIG_CSUM
    if len(img) < 0x20:
        return img
    blockid = img[0]
    if blockid == 0x69:
        print("Image is already marked for UART boot.")
        return img
    sources = {0x78: "SPI", 0x8b: "NAND_X8", 0x9b: "NAND_X16", 0x5a: "SATA", 0xae: "PEX"}
    print(f"Patching header: blockid 0x{blockid:02x} ({sources.get(blockid, 'UNKNOWN')}) → 0x69 (UART)")
    ORIG_BLOCKID = blockid
    ORIG_CSUM = img[0x1F]
    img = bytearray(img)
    img[0] = 0x69
    new_csum = sum(img[:0x1F]) & 0xFF
    print(f"New header checksum at 0x1F: 0x{img[0x1F]:02x} → 0x{new_csum:02x}")
    img[0x1F] = new_csum
    return bytes(img)

def print_unpatch_instructions(image_size, load_addr=0x800000):
    """Print U-Boot commands to undo the UART-boot patch in RAM and write
    the original image to NAND. Only meaningful if we actually patched."""
    if ORIG_BLOCKID is None:
        return
    # Round image size up to a NAND-friendly boundary for nand erase/write
    # (page-aligned; 0x800 = 2 KiB pages on Kirkwood). Caller chooses size.
    print()
    print("=" * 60)
    print("Image is now in RAM at 0x%08x." % load_addr)
    print("Before flashing to NAND, restore the original header so the")
    print("BootROM will accept the image from NAND on next boot.")
    print()
    print("Paste at the U-Boot prompt (one line at a time):")
    print()
    print(f"  mw.b 0x{load_addr:x} {ORIG_BLOCKID:02x} 1")
    print(f"  mw.b 0x{load_addr+0x1f:x} {ORIG_CSUM:02x} 1")
    print(f"  md.b 0x{load_addr:x} 0x20    # verify: first byte should be 0x{ORIG_BLOCKID:02x}, last 0x{ORIG_CSUM:02x}")
    print()
    print("Then flash (size 0x%x is the image size — round up if needed):" % image_size)
    print(f"  nand erase 0x0 0x{image_size:x}")
    print(f"  nand write 0x{load_addr:x} 0x0 0x{image_size:x}")
    print()
    print("Finally:")
    print("  reset")
    print("=" * 60)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("image")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--no-patch", action="store_true", help="don't rewrite the blockid for UART boot")
    args = ap.parse_args()

    with open(args.image, "rb") as f:
        img = f.read()

    if not args.no_patch:
        img = patch_uart_boot(img)

    ser = serial.Serial(args.port, args.baud, timeout=0.1)
    try:
        sense_bootrom(ser)
        send_image(ser, img)
        # afterwards, dump everything coming back (boot log) until Ctrl-C
        print("\nDropping to passive listen (Ctrl-C to exit)...")
        ser.timeout = 1.0
        try:
            while True:
                d = ser.read(4096)
                if d:
                    sys.stdout.write(d.decode('latin-1'))
                    sys.stdout.flush()
        except KeyboardInterrupt:
            print("\nExiting.")
    finally:
        ser.close()

if __name__ == "__main__":
    main()
