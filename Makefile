.PHONY: all clean

ACME ?= acme
OUTPUT := build/ultimate_demo_fixed.prg
SOURCE := deepseek_asm_FIXED_v1_4_clean.s

all: $(OUTPUT)

$(OUTPUT): $(SOURCE)
	@mkdir -p build
	$(ACME) --strict-segments -f cbm -o $@ $(SOURCE)

clean:
	rm -rf build
