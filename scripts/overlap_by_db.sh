#!/bin/bash

# This script creates a CSV per-class-per-DB.
# Each CSV records how many of the RSPL keys in the local DB is found in all other DBs.

set -eu

# shellcheck source=SCRIPTDIR/irr_lists.sh
source "$(dirname "${BASH_SOURCE[0]}")/irr_lists.sh"

INPUT_DIR="data/extracted"
BASE_OUTPUT_DIR="data/overlap_by_db"
rm -rf "$BASE_OUTPUT_DIR" || exit 1
mkdir -p "$BASE_OUTPUT_DIR" || exit 1

# Runs one class to completion; invoked as a background job so
# all classes execute in parallel instead of one after another.
check_class() {
    local CLASS="$1"
    local OUTPUT_DIR A_FILE A_FILE_PATH B_FILE B_FILE_PATH FOUND NOT_FOUND

    echo "Comparing $CLASS"

    OUTPUT_DIR="$BASE_OUTPUT_DIR/$CLASS"
    mkdir -p "$OUTPUT_DIR" || exit 1

    for A_FILE in "${irr_files[@]}"; do
        if [ "$A_FILE" == "apnic.db" ] || [ "$A_FILE" == "ripe.db" ]; then
            A_FILE="$A_FILE.$CLASS"
        fi
        A_FILE_PATH="$INPUT_DIR/$CLASS/$A_FILE"
        echo "Checking $A_FILE_PATH"

        OUTPUT_CSV="$OUTPUT_DIR/$A_FILE.csv"
        echo "file,found,not-found" > "$OUTPUT_CSV"

        for B_FILE in "${irr_files[@]}"; do
            if [ "$B_FILE" == "apnic.db" ] || [ "$B_FILE" == "ripe.db" ]; then
                B_FILE="$B_FILE.$CLASS"
            fi

            if [ "$A_FILE" == "$B_FILE" ]; then
                continue
            fi

            B_FILE_PATH="$INPUT_DIR/$CLASS/$B_FILE"

            # Single awk pass: hash the dst file's lines once, then stream
            # the A file doing O(1) lookups, instead of spawning one
            # grep per A line that re-scans the whole B file.
            # Match on FILENAME rather than NR==FNR, which breaks when the
            # B file is empty (A's lines would be loaded into seen instead).
            read -r FOUND NOT_FOUND <<< "$(awk '
                FILENAME == ARGV[1] { seen[$0]=1; next }
                ($0 in seen) { m++; next }
                { n++ }
                END { print m+0, n+0 }
            ' "$B_FILE_PATH" "$A_FILE_PATH")"

            echo "$B_FILE_PATH,$FOUND,$NOT_FOUND" >> "$OUTPUT_CSV"
        done
    done

    echo "Finished comparing $CLASS"
}

PIDS=()

# Background jobs in a script ignore SIGINT, so Ctrl-C would only kill this
# parent. Run each job in its own process group (set -m) and kill every group,
# including the awk processes they spawn, when interrupted.
set -m
# shellcheck disable=SC2329 # invoked via trap
cleanup() {
    trap - INT TERM
    echo "Interrupted, stopping background jobs" >&2
    for PID in "${PIDS[@]}"; do
        kill -- "-$PID" 2>/dev/null || true
    done
    wait
    exit 130
}
trap cleanup INT TERM

for CLASS in "${classes[@]}"; do
    check_class "$CLASS" &
    PIDS+=("$!")
done

STATUS=0
for PID in "${PIDS[@]}"; do
    wait "$PID" || STATUS=1
done

echo "All comparisons completed"

exit "$STATUS"
