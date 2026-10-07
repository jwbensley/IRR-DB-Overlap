# IRR DB Overlap

A few simple scripts which compare the objects in each RIR and NIR IRRDB. Ultimately, CSV files are generated which show how many RPSL object keys in a given IRRDB, for a given object type (e.g. `as-set`), are found/not-found in all other IRRDBs (the overlap).

The details of each object aren't checked (e.g. if an AS-SET has the same members, or which object was more recently updated), just whether the RPSL key exists in multiple IRR DBs.

Jump to [Finding Matching Keys](#finding-matching-keys) to see the CSV outputs.

## Usage

* Run `./scripts/download_irr_files.py` to download the IRR exports from each RIR and "potentially mirror-able" NIR (i.e. a source of IRR data that may or may not already be incorporated into the IRR exports of an RIR) to [data/packed/](data/packed/) (the script is written in vanilla Python with no dependencies). See [Downloading Data](#downloading-data).
* Run `./scripts/unpack.sh` to decompress the IRR exports.
* Run `./scripts/extract.sh` to extract each class of object from the IRR DB dumps, and write a list of their RSPL keys to separate per-class-per-DB files in [data/extracted/](data/extracted/). See [Extracting Object Keys](#extracting-object-keys).
* Run `./scripts/overlap_by_db.sh` to generate CSV files per-class-per-DB. Each CSV file states how many of the RPSL keys for the related object class (parent folder name) in the local DB, were found in each of the other DBs (how much overlap the local DB has with each other DB). See [Finding Matching Keys](#finding-matching-keys).
* Run `./scripts/overlap_by_class.sh` to combine the per-DB CSVs from [data/matches/](data/matches/) into one matrix CSV per class in [data/matrixes/](data/matrixes/). Each row is a local DB, each column is another DB, and each cell is the number of the row DB's RPSL keys found in the column DB. See [Finding Matching Keys](#finding-matching-keys).

## Findings

### Downloading Data

See the [script source](scripts/download_irr_files.py) for the exact URLs retrieved.

Notes about data sources other than the 5 RIRs which are / are not pulled by the script:

* ~~CNNIC~~: NIR for China. CNNIC don't run their own public IRR database which other networks can mirror. It appears that CNNIC update all their data in APNIC's database. Therefore, nothing to download.
* ~~IDNIC~~: NIR for Indonesia. Data is not downloaded from IDNIC, their mirror is dead.
* ~~IRINN~~: NIR for India. IRINN don't run their own public IRR database which other networks can mirror. IRINN update all their data in APNIC's database.
* JPNIC: NIR for Japan. Their data export contains inetnum, inet6num, and aut-num objects (tracking resource allocations but not routing policy).
  * The route/route6 objects for the inetnum/inet6nums objects in this export, are in the JPIRR export. For example, choose a random inetnum from the JPNIC export like `103.134.34.0 - 103.134.35.255`, there is a route object for `103.134.34.0/23` in the JPIRR export.
  * The data in this export is mirrored into APNIC's public server. For example, choose a random inetnet from the JPNIC export like `inetnum: 103.134.34.0 - 103.134.34.7`, it is visible at APNIC, `whois -h whois.apnic.net 103.134.34.0` returns `inetnum: 103.134.34.0 - 103.134.34.7` with `source: JPNIC`, but it's not included in APNIC's data exports.
* JPIRR: NIR for Japan. Their data export contains as-set, aut-num, mntner, route-set, route, and route6 objects (routing policy but not tracking resource allocations).
  * The inetnum/inet6num objects for the route/route6 objects in this export are in the JPNIC export.
  * None of the data in this export is mirrored into APNIC's public server nor included in APNIC's data exports. For example, choose a random route object from the JPIRR export like `103.134.34.0/23`, it isn't returned by APNIC's server `whois -h whois.apnic.net 103.134.34.0/23`, but the inetnum for the same range (in the JPNIC data export) is returned.
  * Data from JPIRR is in standard RSPL format except that some of the object names are non-standard (e.g. `*xxset` instead of `as-set` and `*xx-num` instead of `aut-num`, etc). The script which downloads the data translates these non-standard object names to the standard object names.
* KRNIC: NIR for South Korea. Their data export contains inetnum, inet6num, and aut-num objects (tracking resource allocations but not routing policy).
  * The data in this export is mirrored into APNIC's public server, and it is included in APNIC's data exports. For example, choose a random inetnum like `inetnum: 211.63.76.0 - 211.63.79.255`, it is returned by APINIC `whois -h whois.lacnic.net 211.63.76.0` as `inetnum: 211.63.76.0 - 211.63.79.255` with `source: KRNIC`.
* NICBR: NIR for Brazil. Their data export "effectively" contains (after it's been converted to RPSL syntax) route and route6 objects (routing policy but not tracking resource allocations).
  * The data in this export isn't mirrored into LACNIC's public servers and it's not in LACNIC's data exports. For example, choose a random route object, you won't see it via LACNIC's whois server `whois -h whois.lacnic.net 45.4.4.0/22` nor routing registry `whois -h irr.lacnic.net 45.4.4.0/22`, but there inetnum/inet6nums are returned by whois.lacnic.net for the route/route6 objects.
  * Data pulled from NICBR is not in the standard RSPL format so it is translated into standard RPSL format by the script which downloads it.
* NTTCOM: Non-authoritative 3rd party DB. Their data export contains as-set, aut-num, mntner, route-set, route, and route6 objects (routing policy and resource allocations).
  * Mirrored / imported by anyone   ################################################################
* RADB: Non-authoritative 3rd party DB. Their data export contains as-set, aut-num, inet6num, inetnum, mntner, route-set, route, and route6 objects (routing policy and resource allocations).
  * Mirrored / imported by anyone   ################################################################
* TC: NIR for Brazil. Their data export contains as-set, aut-num, inet6num, inetnum, mntner, route, route6, and route-set objects (routing policy and resource allocations).
  * Some of the data in this export is mirrored into LACNIC's public server, but none of it is in LACNIC's data exports. For example, choose a random resource allocation like an aut-num or inetnum and you'll see in via LACNIC's public server `whois -h irr.lacnic.net AS16735`.
* TWNIC: NIR for Taiwan. Their data export contains inetnum and inet6nums objects (resource allocations but not routing policy).
  * The data in this export is mirrored into APNIC's public server, but it's not in APNIC's data exports.

### Extracting Object Keys

The JPIRR data contains objects with duplicated RPSL keys. These are stored under [data/jpirr_dupes](data/jpirr_dupes) by RPSL class.

An example chosen at random:

```text
aut-num:    AS45691
as-name:    JPIRR
descr:      DODONET-CORE
notify:     noc@biz.dodo.ad.jp
admin-c:    JP00242721
tech-c:     JP00242721
mnt-by:     MAINT-AS45691
changed:    noc@biz.dodo.ad.jp 20240904
source:     JPIRR

aut-num:    AS45691
as-name:    JPIRR
descr:      DODO_Core_JP
notify:     noc@biz.dodo.ad.jp
admin-c:    JP00242721
tech-c:     JP00242721
mnt-by:     MAINT-AS45691
changed:    noc@biz.dodo.ad.jp 20241016
source:     JPIRR
```

Are the multiple versions simply for tracking changes over time, and only the most recently changed object should be used?

The number of unique RPSL keys:

```text
$ wc -l data/extracted/*/jpirr.db
   356 data/extracted/as-set/jpirr.db
   486 data/extracted/aut-num/jpirr.db
     0 data/extracted/inet6num/jpirr.db
     0 data/extracted/inetnum/jpirr.db
   447 data/extracted/mntner/jpirr.db
  1366 data/extracted/route6/jpirr.db
 13999 data/extracted/route/jpirr.db
     1 data/extracted/route-set/jpirr.db
 16655 total
```

The number of duplicated RPSL keys:

```text
$ wc -l data/jpirr_dupes/*
   0 jpirr_dupes/as-set
   1 jpirr_dupes/aut-num
   0 jpirr_dupes/inet6num
   0 jpirr_dupes/inetnum
   0 jpirr_dupes/mntner
 218 jpirr_dupes/route
  14 jpirr_dupes/route6
   0 jpirr_dupes/route-set
 233 total
```

Data from JPIRR is in standard RSPL format except that some of the object names are non-standard (e.g. `*xxset` instead of `as-set` and `*xx-num` instead of `aut-num`, etc). The script which downloads the data can translate these non-standard object names to the standard object names.

```text
rm data/packed/jpirr.db.gz
./scripts/download_irr_files.py -j
./scripts/unpack.sh
./scripts/extract.sh
```

The number of unique RPSL keys found in the JPIRR data has barely increase:

```text
$ wc -l data/extracted/*/jpirr.db
   356 data/extracted/as-set/jpirr.db
   487 data/extracted/aut-num/jpirr.db
     0 data/extracted/inet6num/jpirr.db
     0 data/extracted/inetnum/jpirr.db
   448 data/extracted/mntner/jpirr.db
  1366 data/extracted/route6/jpirr.db
 14006 data/extracted/route/jpirr.db
     1 data/extracted/route-set/jpirr.db
 16664 total
```

The number of duplicated RPSL keys has significantly increased:

```text
$ wc -l data/jpirr_dupes/*
   51 data/jpirr_dupes/as-set
   42 data/jpirr_dupes/aut-num
    0 data/jpirr_dupes/inet6num
    0 data/jpirr_dupes/inetnum
   33 data/jpirr_dupes/mntner
  840 data/jpirr_dupes/route
   89 data/jpirr_dupes/route6
    0 data/jpirr_dupes/route-set
 1055 total
```

Upon a cursory manual look, all of the duplicate objects with the non-standard RPSL keys have older last modified dates, so they appear to be historical/change references.

### Finding Matching Keys

CSV outputs stored in [data/overlap_by_db](data/overlap_by_db/) show on a per-class level, the overlap for a single database vs all over databases.

Looking at [data/overlap_by_db/as-set/afrinic.db.csv](data/overlap_by_db/as-set/afrinic.db.csv) as an example:

```csv
file,found,not-found
data/extracted/as-set/apnic.db.as-set,8,1559
data/extracted/as-set/arin.db,21,1546
data/extracted/as-set/jpirr.db,0,1567
data/extracted/as-set/jpnic.db,0,1567
data/extracted/as-set/krnic.db,0,1567
data/extracted/as-set/lacnic.db,0,1567
data/extracted/as-set/nicbr-asn-blk-latest.txt,0,1567
data/extracted/as-set/nttcom.db,2,1565
data/extracted/as-set/radb.db,53,1514
data/extracted/as-set/ripe.db.as-set,167,1400
data/extracted/as-set/tc.db,0,1567
data/extracted/as-set/twnic.db,0,1567
```

The first row of this CSV file shows that of the 1567 as-set's in the `afrinic.db` file, 8 as-set's were found in `apnic.db.as-set` with the same RPSL key, the remaining 1559 weren't found in APNIC (there is minimal overlap of as-set's between these database exports for this object type). Further down the table; 0 of the as-set's in `afrinic.db` where found in `lacnic.db`, 1567 (100%) weren't found in LACNIC (therefore is no overlap of as-set names between these two databases).

The CSV outputs stored in [data/overlap_by_class/](data/overlap_by_class/) show on a per-class level, the overlap between all databases.

## Additional Stats

With all the extracted data a few additional checks can easily be made.

### Number of RPSL Keys per DB

How many unique RPSL keys does each database export contain, and how many per class type.

```text
./scripts/key_count.sh 
```

See [data/key_count.csv](data/key_count.csv)

### Unique Sources

Do any of the downloaded data exports reference data from sources other than those which have been downloaded, suggesting these aren't all the RIRs and possible NIRs:

```text
$ grep -E "^source:" -h -r data/unpacked/* | awk '{print toupper($2)}' | sort | uniq
AFRINIC
APNIC
ARIN
JPIRR
JPNIC
KRNIC
LACNIC
NICBR
NTTCOM
RADB
RIPE
RIPE#
TC
TWNIC
```

No.

### Cross-DB Origin ASNs

Generate a list of ASNs, and for each ASN which database exports contain route/route6 objects with that ASN as an origin. This shows which ASNs are used as origins for routes stored in multiple databases:

```text
./scripts/asns.sh
Wrote 93688 ASNs to data/asns//asns.txt
```

See [data/asns/asns.txt](data/asns/asns.txt)

Count the frequency of ASN-to-file instances:

```text
./scripts/asn_freq.sh
```

See [data/asns/asn_freq.txt](data/asns/asn_freq.txt)
