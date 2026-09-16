# DeepSeek fixed v1.4 clean

PAL C64 demo source with multi-raster IRQs, sprites, scroller, plasma, and
decorative logo effects.

## Build and run

```sh
acme --strict-segments -f cbm -o ultimate_demo_fixed.prg \
  deepseek_asm_FIXED_v1_4_clean.s
x64sc -autostart ultimate_demo_fixed.prg
```

The audit removed duplicate local labels and dead duplicate scroller code,
restored the missing sprite/color update work, fixed initial color setup, and
made carry handling explicit in the raster-bar phase. See `AUDIT.md`.
