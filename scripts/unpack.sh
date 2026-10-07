#!/bin/bash

# A script to unpack all compressed files (or simply copy uncompressed files) from the packed directory to the unpacked directory. 

set -eu

INPUT_DIR="data/packed"
OUTPUT_DIR="data/unpacked"

# Remove any existing files in the unpacked directory to ensure a clean state
# shellcheck disable=SC2115
rm -rf "$OUTPUT_DIR"/* || exit 1
mkdir -p "$OUTPUT_DIR" || exit 1

for FILE in "$INPUT_DIR"/*; do
    if [[ "$FILE" == *.gz ]]; then
        gzip -dc "$FILE" > "$OUTPUT_DIR/$(basename "$FILE" .gz)"
    else
        cp "$FILE" "$OUTPUT_DIR/"
    fi
done

echo "All files unpacked to $OUTPUT_DIR directory."
