# C64 v1.4

Cleaned PAL C64 demo source with multi-raster IRQs, sprites, scroller, plasma,
and decorative logo effects.

## Build

Requires ACME 0.97 or newer:

```sh
make
```

The reproducible output is `build/c64_raster_plasma_scroller.prg`. To run it with VICE:

```sh
x64sc -autostart build/c64_raster_plasma_scroller.prg
```

## Repository layout

- `c64_raster_plasma_scroller.s` — corrected source.
- `Makefile` — strict ACME build and clean targets.
- `AUDIT.md` — issue-by-issue repair record and validation contract.
- `SHA256SUMS.txt` — checksums for tracked files.

## Audit summary

The audit removed duplicate local labels and dead duplicate scroller code,
restored the missing sprite/color update work, fixed startup color setup, and
made raster carry handling explicit. The original `$0801`/`SYS 4608` entry
contract is preserved.
