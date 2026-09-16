# Audit record

The original source did not assemble under ACME because `.doShift`, `.shift`,
`.ok`, and `.noloop` were defined twice in one local-label scope. The second
dead duplicate scroller implementation was removed.

Additional repairs:

- IRQ2 now runs the sprite and color-wave work promised by its header.
- Startup initializes the background color explicitly instead of storing the
  CIA mask value `$7F` in `$D021`.
- Fine-scroll setup no longer contains contradictory dead register operations.
- Raster-bar addition clears carry before the second `ADC`.

Validation: ACME `--strict-segments` succeeds and produces a CBM PRG with the
existing `$0801`/`SYS 4608` entry contract.

Corrected build SHA-256: `181c14d8b6edc120abd821ac54002f29b383ca0f78789d4e11ef3b6cab586624`.
