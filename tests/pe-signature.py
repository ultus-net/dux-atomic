#!/usr/bin/env python3
"""Write the PKCS#7 signature from a PE image's certificate table to stdout.

A kernel in a Fedora bootc image is a PE binary, and its Authenticode signature
lives in data directory 4. Before that, Fedora's kernels carry a PE wrapper only
for this signature, so a signed vmlinuz and an unsigned one differ by nothing but
this table.

A missing or empty table exits 1, so a caller can tell an unsigned kernel from a
parse failure. Diagnostics go to stderr; stdout carries only the DER blob, so the
output pipes into `openssl pkcs7 -inform DER`.
"""

import struct
import sys


def read_signature(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:2] != b"MZ":
        raise SystemExit(f"{path}: no MZ header, so it is not a PE image")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe : pe + 4] != b"PE\0\0":
        raise SystemExit(f"{path}: no PE header at offset {pe}")
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    if magic == 0x20B:
        directories = optional + 112
    elif magic == 0x10B:
        directories = optional + 96
    else:
        raise SystemExit(f"{path}: unknown optional header magic {magic:#x}")
    offset, size = struct.unpack_from("<II", data, directories + 4 * 8)
    if size == 0:
        raise SystemExit(f"{path}: the certificate table is empty, so it is unsigned")
    if offset + size > len(data):
        raise SystemExit(f"{path}: the certificate table runs past the end of the file")
    length, revision, cert_type = struct.unpack_from("<IHH", data, offset)
    if length < 8 or length > size:
        raise SystemExit(
            f"{path}: the certificate table says {length} bytes, which does not fit its {size}"
        )
    if cert_type != 0x2:
        raise SystemExit(
            f"{path}: the certificate table holds type {cert_type:#x}, not PKCS#7 (0x2)"
        )
    sys.stderr.write(f"{path}: PKCS#7 revision {revision:#x}, {length - 8} bytes\n")
    return data[offset + 8 : offset + length]


def main(argv):
    if len(argv) != 2:
        raise SystemExit("usage: pe-signature.py <pe-image>")
    sys.stdout.buffer.write(read_signature(argv[1]))


if __name__ == "__main__":
    main(sys.argv)
