# Known gaps before promotion

- `console=ttyS0,115200` ships a serial getty to every install. It is a deliberate VM-test and recovery console for this branch; gate it behind a test build before publishing.
- The image has no NVIDIA variant, application set, agent sandbox, or snapshot automation yet. The README marks these as planned.
- The VM test covers the greeter and a serial login. It does not log in through the greeter, start a second session, or exercise the Xfce fallback.
- CI runs the boot test on TCG and does not render or inspect the desktop. The graphical dogfood stays a local pre-promotion step.
- The test disk raises `systemd.default_device_timeout_sec` to 180s so slow TCG boots reach `/boot`. CI therefore cannot catch a regression that only exceeds the shipped 45s.
- `bootc-image-builder` is pinned in `tests/vm/make-disk.sh`, but the base image tag floats and the COPR packages are unpinned (#2).
- The first-login retry has unit fixtures and a VM marker assertion, but no partial-home VM coverage yet. Rebuild and re-run the graphical dogfood after the retry change.
- The attested SBOM lists packages only. `build/sbom-packages-only.jq` drops the 86111 RPM-owned file entries and their relationships because Rekor's public instance answered 502 for the 86 MB DSSE body; a replay reached the service at 16 MB and was rejected at 32 MB. File-level hashes are therefore not attested, and a larger package set could approach the limit again.
- `publish` retries signing and attesting for about fifteen minutes per command before it fails, so a permanent error costs that waiting time before the run goes red.
