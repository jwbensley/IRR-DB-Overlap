#!/bin/bash

# This script generates a CSV file with the number of RPSL keys per data source, per class type.
# It is assumed that the input data (RSPL keys) has been deduped.
# It also adds a total count of all RSPL keys for that data source.

set -eu
shopt -s nullglob

# shellcheck source=SCRIPTDIR/irr_lists.sh
source "$(dirname "${BASH_SOURCE[0]}")/irr_lists.sh"

INPUT_DIR="data/extracted"
OUTPUT_FILE="data/key_count.csv"
# One column per sub-folder of the input dir.
CLASS_DIRS=("${INPUT_DIR}"/*/)
CLASS_DIRS=("${CLASS_DIRS[@]%/}")

{
    HEADER="file"
    for DIR in "${CLASS_DIRS[@]}"; do
        HEADER+=",$(basename "$DIR")"
    done
    printf "%s" "${HEADER},total"

    for FILE in "${irr_files[@]}"; do
        ROW="$FILE"
        TOTAL=0
        for DIR in "${CLASS_DIRS[@]}"; do
            # Some sources are split per class, e.g. apnic.db.as-set
            MATCHES=("${DIR}/${FILE}"*)
            COUNT=0
            if [ "${#MATCHES[@]}" -gt 0 ]; then
                COUNT=$(cat "${MATCHES[@]}" | wc -l)
            fi
            ROW+=",${COUNT}"
            TOTAL=$((TOTAL + COUNT))
        done
        # Newline before each row so the file has no trailing newline.
        printf "\n%s" "${ROW},${TOTAL}"
    done
} > "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
