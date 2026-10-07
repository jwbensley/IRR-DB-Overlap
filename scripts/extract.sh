#!/bin/bash

# This script will extract the RPSL key for each object from the IRR DB dumps, and write them to separate per-class-per-DB files in extracted/

set -eu

# shellcheck source=SCRIPTDIR/irr_lists.sh
source "$(dirname "${BASH_SOURCE[0]}")/irr_lists.sh"

INPUT_DIR="data/unpacked"
BASE_OUTPUT_DIR="data/extracted"
JPIRR_DUPES="data/jpirr_dupes"
rm -rf "$BASE_OUTPUT_DIR" || exit 1
rm -rf "$JPIRR_DUPES" || exit 1
mkdir -p "$BASE_OUTPUT_DIR" || exit 1
mkdir -p "$JPIRR_DUPES" || exit

for CLASS in "${classes[@]}"; do

    echo "Extracting $CLASS"

    OUTPUT_DIR="$BASE_OUTPUT_DIR/$CLASS"
    mkdir -p "$OUTPUT_DIR" || exit 1
    for FILE in "${irr_files[@]}"; do
        if [ "$FILE" == "apnic.db" ] || [ "$FILE" == "ripe.db" ]; then
            FILE="$FILE.$CLASS"
        fi

        if [ "$CLASS" == "route" ] || [ "$CLASS" == "inetnum" ]; then
            SORT="sort -t . -k1,1n -k2,2n -k3,3n -k4,4n"
        else
            SORT="sort"
        fi

        # JPIRR has duplicate AS-SETs with different members, inside the same IRR DB ?!?!
        # Let's track them separately.
        if [ "$FILE" == "jpirr.db" ]; then
            # Only write entries which appear more than once
            grep -aE "^$CLASS: " "$INPUT_DIR/$FILE" | awk '{sub(/^[^:]+:[ \t]*/, ""); print}' | $SORT | uniq -d > "$JPIRR_DUPES/$CLASS"
        fi

        grep -aE "^$CLASS: " "$INPUT_DIR/$FILE" | awk '{sub(/^[^:]+:[ \t]*/, ""); print}' | $SORT  | uniq > "$OUTPUT_DIR/$FILE"
    done

done
