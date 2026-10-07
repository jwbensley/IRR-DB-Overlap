#!/bin/bash

# This script will loop over every file in unpacked/* and look for lines which begin match the regex "^origin: ".
# E.g.
# origin:         AS46133
# The script will extract the last field (the AS number) and build a list of tuples,
# the first value being an AS number and the second value being the files they were found in
# E.g.
# (AS1111, (arin.db)),
# (AS2222, (arin.db, ripe.db))
# The end result is a list of ASNs (taken from route/route6 objects) and which DBs contain route/route6 objects
# that use those ASNs as an origin, to show which ASNs are origins of routes stored in different DBs.

set -eu

INPUT_DIR="data/unpacked"
OUTPUT_DIR="data/asns/"
OUTPUT_FILE="$OUTPUT_DIR/asns.txt"

rm -rf "$OUTPUT_DIR" || exit 1
mkdir -p "$OUTPUT_DIR" || exit 1

files=()
for f in "$INPUT_DIR"/*; do
    [ -f "$f" ] && files+=("$f")
done

# Single awk pass over every file: hash (asn, file) pairs so each file is
# only recorded once per ASN, then emit the tuples sorted numerically by ASN.
awk '
FNR == 1 {
    file = FILENAME
    sub(/^.*\//, "", file)
    # Some sources are split per class, e.g. ripe.db.route and ripe.db.route6,
    # treat these as a single DB so an ASN is only counted once per source.
    sub(/\.db\..*$/, ".db", file)
}
/^origin:[ \t]/ {
    line = $0
    sub(/#.*/, "", line)
    cnt = split(line, parts)
    asn = toupper(parts[cnt])
    key = asn SUBSEP file
    if (key in seen) next
    seen[key] = 1
    if (!(asn in files_by_asn)) asn_order[++n] = asn
    files_by_asn[asn] = files_by_asn[asn] (files_by_asn[asn] == "" ? "" : ",") file
}
END {
    for (i = 1; i <= n; i++) {
        asn = asn_order[i]
        print asn, files_by_asn[asn]
    }
}
' "${files[@]}" | sort -k1.3n | awk '{
    n = split($2, f, ",")
    line = "(" $1 ", ("
    for (i = 1; i <= n; i++) {
        line = line f[i]
        if (i < n) line = line ", "
    }
    line = line "))"
    print line
}' > "$OUTPUT_FILE"

echo "Wrote $(wc -l < "$OUTPUT_FILE") ASNs to $OUTPUT_FILE"
