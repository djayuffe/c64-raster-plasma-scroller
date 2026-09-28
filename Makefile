.PHONY: all clean check checksums

ACME ?= acme
OUTPUT := build/c64_raster_plasma_scroller.prg
SOURCE := c64_raster_plasma_scroller.s
CHECKSUM_INPUTS := .gitignore AUDIT.md LICENSE Makefile NOTICE README.md \
    c64_raster_plasma_scroller.s docs/FUNCTIONS.md docs/EFFECTS.md docs/preview.png \
    $(wildcard assets/effects/*.png)

all: $(OUTPUT)

$(OUTPUT): $(SOURCE)
	@mkdir -p build
	$(ACME) --strict-segments -f cbm -o $@ $(SOURCE)

clean:
	rm -rf build

checksums:
	@shasum -a 256 $(CHECKSUM_INPUTS) > SHA256SUMS.txt

check: $(OUTPUT)
	@test "$(shell od -An -tx1 -N2 $(OUTPUT) | tr -d ' \n')" = "0108"
	@test "$(shell wc -c < $(OUTPUT))" -gt 1024
	@shasum -a 256 -c SHA256SUMS.txt
