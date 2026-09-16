# Function reference

This build is the raster-plasma/scroller variant.

| Function | Responsibility |
|---|---|
| Start / InitState | Establishes VIC/CIA state and initializes effect tables. |
| SyncFrame | Synchronizes the frame before effect updates. |
| UpdateScroll | Advances the bottom message and handles wraparound. |
| UpdateSprites | Updates sine-driven sprite positions using protected indices. |
| ColorWaveEffect / PlasmaEffect | Generates animated color fields. |
| RasterBars | Produces timed raster color changes. |
| DrawLogo / DrawBorders | Renders the logo and decorative borders. |
| IRQ1–IRQ4 | Chained raster handlers for the frame sections. |

The generated PRG keeps the original $0801/SYS 4608 entry contract.
