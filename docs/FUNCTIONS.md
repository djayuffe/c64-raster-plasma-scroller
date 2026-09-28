# Routine reference

The source is a single ACME module. Labels below are the public execution
points and the state they read or update.

| Routine | Role | Main state/registers |
| --- | --- | --- |
| `Start` | BASIC target; installs vectors, VIC mode, and frame IRQ | `$01`, VIC/CIA IRQ registers |
| `InitState` | Clears phase, scroll, and colour counters | `FrameCount`, `ScrollIdx`, phases |
| `SyncFrame` | Waits for a frame boundary before scheduling work | `FrameCount` |
| `IRQ1` | Top rainbow raster; chains to `IRQ2` | VIC raster register, `ColorCycle` |
| `IRQ2` | Sprite motion and row colour wave | `StarPhase`, `WavePhase` |
| `IRQ3` | Plasma rows and smooth scroller | `PlasmaPhase`, `SmoothScroll` |
| `IRQ4` | Bottom raster bars; closes the chain | `ColorCycle` |
| `UpdateScroll` | Advances text index and fine scroll; wraps safely | `ScrollIdx`, `SmoothScroll` |
| `UpdateSprites` | Updates eight sprite coordinates/colours from tables | `StarPhase`, VIC sprite regs |
| `ColorWaveEffect` | Writes the animated row colour gradient | `WavePhase`, colour RAM |
| `PlasmaEffect` | Computes table-driven plasma colour values | `PlasmaPhase`, colour RAM |
| `RasterBars` | Emits the lower raster-bar palette sequence | VIC border/background |
| `DrawLogo` | Writes the static logo glyphs and colours | screen/colour RAM |
| `DrawBorders` | Draws the decorative frame | screen/colour RAM |
| `CopyROMCharset` | Copies ROM glyph data into RAM at `$2000` | `$2000-$27FF` |
| `ModifyCharset` | Applies custom glyph edits | `$2000-$27FF` |
| `CreateSpriteData` | Builds sprite bitmaps in RAM | `$2800-$29FF` |
| `ClearScreen` / `ClearColor` | Deterministic initial buffers | `$0400-$07E7`, `$D800-$DBE7` |
| `NMI_Handler` | Safe NMI return path | processor state |

## Boot and IRQ flow

The `$0801` BASIC stub executes `SYS 4608`, entering `Start` at `$1200`.
Initialisation selects VIC bank 0, maps screen RAM to `$0400`, maps the custom
charset to `$2000`, clears buffers, prepares the logo/borders/sprites, and arms
the raster IRQ. `Forever` then keeps the main code alive while the IRQ chain
drives the image.

Each IRQ acknowledges the VIC raster flag, performs its bounded update, writes
the next raster compare value, and returns through the common 6502 interrupt
epilogue. The fixed order is approximately 50 → 100 → 150 → 200 → 50 lines.

## State and safety conventions

- Phase counters are byte-sized and wrap modulo 256 for cheap table indexing.
- Scroll and message indexes wrap at the table terminator; no effect reads past
  its source data.
- Sprite coordinates are generated from bounded tables before being written to
  VIC registers.
- Startup explicitly sets the border/background colour and clears CIA/VIC IRQ
  sources, so a warm boot does not inherit host state.
- Assembly is built with ACME `--strict-segments`; CI additionally verifies the
  `$0801` PRG load address and a non-trivial output size.
