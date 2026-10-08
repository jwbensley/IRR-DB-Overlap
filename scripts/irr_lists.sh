#!/bin/bash

# Shared lists of IRR DB files and RPSL object classes.
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/irr_lists.sh"

# shellcheck disable=SC2034
irr_files=(
    "afrinic.db"
    "apnic.db"
    "arin.db"
    "jpirr.db"
    "jpnic.db"
    "krnic.db"
    "lacnic.db"
    "nicbr-asn-blk-latest.txt"
    "radb.db"
    "ripe.db"
    "tc.db"
    "twnic.db"
)

# shellcheck disable=SC2034
classes=(
    "as-set"
    "aut-num"
    "route"
    "route6"
    "mntner"
    "inetnum"
    "inet6num"
    "route-set"
)
