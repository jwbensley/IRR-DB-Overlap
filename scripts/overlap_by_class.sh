#!/bin/bash

# This script reads in all the CSV files in data/overlap_by_db/*/*.csv and creates combined overlap matrixes in data/overlap_by_class/
# One matrix CSV is created per class. Each row is a local DB and each column is another DB,
# the cell value is how many of the row DB's RPSL keys were found in the column DB.
# A DB isn't compared to itself, so those cells are left empty.

set -eu
shopt -s nullglob

INPUT_DIR="data/overlap_by_db"
OUTPUT_DIR="data/overlap_by_class"
rm -rf "$OUTPUT_DIR" || exit 1
mkdir -p "$OUTPUT_DIR" || exit 1

CLASS_DIRS=("${INPUT_DIR}"/*/)
CLASS_DIRS=("${CLASS_DIRS[@]%/}")

for DIR in "${CLASS_DIRS[@]}"; do
    CLASS="$(basename "$DIR")"
    CSV_FILES=("${DIR}"/*.csv)
    if [ "${#CSV_FILES[@]}" -eq 0 ]; then
        continue
    fi

    echo "Creating matrix for $CLASS"

    # Some sources are split per class, e.g. apnic.db.as-set, so strip the
    # class suffix to keep the DB names consistent across all matrixes.
    awk -F, -v class="$CLASS" '
        function db_name(path) {
            sub(/.*\//, "", path)
            sub(/\.csv$/, "", path)
            sub("\\." class "$", "", path)
            return path
        }
        FNR == 1 { row = db_name(FILENAME); rows[++n] = row; next }
        { matches[row, db_name($1)] = $2 }
        END {
            line = "file"
            for (i = 1; i <= n; i++) line = line "," rows[i]
            printf "%s", line
            for (i = 1; i <= n; i++) {
                line = rows[i]
                for (j = 1; j <= n; j++) {
                    line = line "," (i == j ? "" : matches[rows[i], rows[j]])
                }
                # Newline before each row so the file has no trailing newline.
                printf "\n%s", line
            }
        }
    ' "${CSV_FILES[@]}" > "$OUTPUT_DIR/$CLASS.csv"
done

echo "All matrixes created"
