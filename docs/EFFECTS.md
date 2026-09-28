# Effect notes

The demo is one continuous PAL frame pipeline rather than a scene switcher.
Each raster stage updates only the data needed for its visual region, keeping
the IRQ work bounded and making the combined image stable on real hardware.

## Frame pipeline

1. `SyncFrame` waits for the next frame and resets per-frame phase work.
2. `IRQ1` paints the top rainbow raster and schedules line 100.
3. `IRQ2` advances sprite positions and the colour wave, then schedules line 150.
4. `IRQ3` advances the smooth scroller and plasma rows, then schedules line 200.
5. `IRQ4` draws the lower raster bars and schedules the next frame's `IRQ1`.

The IRQ handler acknowledges the VIC raster flag before doing effect work and
preserves the processor state expected by the common return path.

## Components

- **Rainbow raster (`IRQ1`)**: writes a short colour sequence during the top
  border window, producing the bright horizontal band in the first capture.
- **Sprite choreography (`IRQ2`/`UpdateSprites`)**: indexes sine tables with
  phase offsets so the eight multicolor sprites move as a wave. Sprite colour
  registers are updated alongside coordinates.
- **Colour wave (`ColorWaveEffect`)**: walks screen rows with a phase counter,
  giving the playfield a moving colour gradient without rewriting character codes.
- **Plasma (`IRQ3`/`PlasmaEffect`)**: combines table lookups for the current
  row and frame phase, then writes colour RAM. The result is a low-cost,
  repeatable C64 plasma field.
- **Scroller (`UpdateScroll`)**: advances the message at character cadence,
  applies fine scroll to the VIC, and wraps the message index safely.
- **Raster bars (`IRQ4`/`RasterBars`)**: emits the lower colour sequence and
  returns control to the first raster stage.
- **Logo and borders**: `DrawLogo` and `DrawBorders` populate screen and colour
  RAM once during initialisation; later IRQs animate around those static areas.
- **Charset**: `CopyROMCharset` moves the ROM glyphs into `$2000`, while
  `ModifyCharset` applies the demo-specific glyph changes before display.

## Captures

The following are representative live VICE frames from the built PRG. Since
the effects overlap continuously, each filename names the component being
documented rather than claiming an isolated scene.

![IRQ1 rainbow](../assets/effects/00-irq1-rainbow.png)
![IRQ2 sprites](../assets/effects/01-irq2-sprites.png)
![IRQ3 plasma](../assets/effects/02-irq3-plasma.png)
![Scroller](../assets/effects/03-irq3-scroller.png)
![IRQ4 raster bars](../assets/effects/04-irq4-raster-bars.png)
![Logo and borders](../assets/effects/05-logo-and-borders.png)
![Charset](../assets/effects/06-charset.png)

For routine ownership and state variables, see [FUNCTIONS.md](FUNCTIONS.md).

