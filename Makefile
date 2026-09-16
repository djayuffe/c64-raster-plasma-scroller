.PHONY: all clean

ACME ?= acme
OUTPUT := build/deepseek_c64_v1_4.prg
SOURCE := deepseek_c64_v1_4.s

all: $(OUTPUT)

$(OUTPUT): $(SOURCE)
	@mkdir -p build
	$(ACME) --strict-segments -f cbm -o $@ $(SOURCE)

clean:
	rm -rf build
