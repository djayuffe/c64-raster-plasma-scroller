.PHONY: all clean

ACME ?= acme
OUTPUT := build/c64_raster_plasma_scroller.prg
SOURCE := c64_raster_plasma_scroller.s

all: $(OUTPUT)

$(OUTPUT): $(SOURCE)
	@mkdir -p build
	$(ACME) --strict-segments -f cbm -o $@ $(SOURCE)

clean:
	rm -rf build
