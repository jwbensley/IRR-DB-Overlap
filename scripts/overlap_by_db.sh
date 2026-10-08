#!/bin/bash

# This script reads in all the CSV files in data/overlap_by_class_by_db/*/*.csv and creates combined overlap matrixes in data/overlap_by_db/
# One matrix CSV is created per DB. Each row is another DB and each column is a class,
# the cell value is the percentage of the local DB's RPSL keys of that class which were found in the row DB.
# A DB isn't compared to itself, so the cells in its own row are left empty. Cells are also left
# empty when the local DB has no keys for the class, as there is no percentage to calculate.

set -eu
shopt -s nullglob

INPUT_DIR="data/overlap_by_class_by_db"
OUTPUT_DIR="data/overlap_by_db"
rm -rf "$OUTPUT_DIR" || exit 1
mkdir -p "$OUTPUT_DIR" || exit 1

CSV_FILES=("${INPUT_DIR}"/*/*.csv)
if [ "${#CSV_FILES[@]}" -eq 0 ]; then
    echo "No CSV files found in $INPUT_DIR" >&2
    exit 1
fi

echo "Creating matrixes for all DBs"

# Some sources are split per class, e.g. apnic.db.as-set, so strip the
# class suffix to keep the DB names consistent across all matrixes.
# LC_NUMERIC=C ensures a "." decimal separator, a "," would break the CSV.
LC_NUMERIC=C awk -F, -v out_dir="$OUTPUT_DIR" '
    function db_name(path, class) {
        sub(/.*\//, "", path)
        sub(/\.csv$/, "", path)
        sub("\\." class "$", "", path)
        return path
    }
    # found + not-found is the total number of keys of this class in the local DB.
    function percent(found, not_found) {
        if (found + not_found == 0) return ""
        return sprintf("%.2f", found * 100 / (found + not_found))
    }
    FNR == 1 {
        # The parent directory of each input CSV is the class name.
        class = FILENAME
        sub(/\/[^\/]*$/, "", class)
        sub(/.*\//, "", class)
        if (!(class in class_seen)) { class_seen[class] = 1; classes[++c] = class }
        db = db_name(FILENAME, class)
        if (!(db in db_seen)) { db_seen[db] = 1; dbs[++n] = db }
        next
    }
    { matches[db, db_name($1, class), class] = percent($2, $3) }
    END {
        for (i = 1; i <= n; i++) {
            out = out_dir "/" dbs[i] ".csv"
            line = "file"
            for (k = 1; k <= c; k++) line = line "," classes[k]
            printf "%s", line > out
            for (j = 1; j <= n; j++) {
                line = dbs[j]
                for (k = 1; k <= c; k++) {
                    line = line "," (i == j ? "" : matches[dbs[i], dbs[j], classes[k]])
                }
                # Newline before each row so the file has no trailing newline.
                printf "\n%s", line > out
            }
            close(out)
        }
    }
' "${CSV_FILES[@]}"

echo "All matrixes created"
