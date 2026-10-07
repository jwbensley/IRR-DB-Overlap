#!/bin/bash

# Reads asns.txt (produced by asns.sh) and counts how many ASNs appear
# in exactly N files, e.g. "1000 ASNs appear in 1 file".

set -eu

INPUT_FILE="data/asns/asns.txt"
OUTPUT_FILE="data/asns/asn_freq.txt"

awk '{
    line = $0
    sub(/^[^,]*, \(/, "", line)
    sub(/\)\)$/, "", line)
    n = split(line, f, ", ")
    freq[n]++
    total++
}
END {
    for (n in freq) print n, freq[n], (freq[n] * 100.0 / total)
}' "$INPUT_FILE" | sort -n > "$OUTPUT_FILE.tmp"

{
    printf "%-12s%-12s%s\n" "num_files" "num_asns" "pct"
    awk '{ printf "%-12s%-12s%.2f%%\n", $1, $2, $3 }' "$OUTPUT_FILE.tmp"
} > "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.tmp"

cat "$OUTPUT_FILE"
