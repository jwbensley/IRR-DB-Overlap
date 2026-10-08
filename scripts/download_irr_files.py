#!/usr/bin/env python3

"""
This script will download database exports from the five RIRs and "potential" NIRs,
so that they can be later compered for overlaps/uniqueness.
"""

from __future__ import annotations

import gzip
import ipaddress
import logging
import os
import sys
import urllib.error
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, as_completed
from enum import Enum

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(threadName)s - %(levelname)s - %(message)s",
)


class IrrParser:
    @staticmethod
    def parse_standard(data: bytes) -> bytes:
        """
        Standard RPSL format, no translation needed.
        """
        logger.info("No translation needed for standard RPSL data")
        return data

    @staticmethod
    def parse_jpirr(data: bytes) -> bytes:
        """
        JPNIC does actually use standard RPSL format, but I assume they have non-ASCII
        characters in their data? An AS-SET object is defined as "*xxset" instead of "as-set", and so on.
        """
        logger.info("Translating JPNIC data to RPSL format")

        # Mapping of JIPNIC-specific prefixes to standard RPSL attributes
        JPNIC_AS_SET = "*xxset:"
        JPNIC_AUT_NUM = "*xx-num:"
        JPNIC_MNTNER = "*xxner:"
        JPNIC_ROUTE = "*xxte:"
        JPNIC_ROUTE6 = "*xxte6:"
        RPSL_MAPPINGS = {
            JPNIC_AS_SET: "as-set:",
            JPNIC_AUT_NUM: "aut-num:",
            JPNIC_MNTNER: "mntner:",
            JPNIC_ROUTE: "route:",
            JPNIC_ROUTE6: "route6:",
        }

        rpsl_lines: list[str] = []

        lines = data.splitlines()
        for raw_line in lines:
            line = raw_line.decode()

            """
            Sometimes we see multiline descriptions:
            descr:      Isahaya Cable Media Co.,Ltd
                        X-keiro : networkalert@icv-net.co.jp
            
            We need to maintain the indentation.

            Therefore don't .strip()/.lstrip() every line,
            just .lstrip() where needed.
            """

            if line.lstrip().startswith(JPNIC_AS_SET):
                line = line.lstrip().replace(
                    JPNIC_AS_SET, RPSL_MAPPINGS[JPNIC_AS_SET]
                )

            elif line.lstrip().startswith(JPNIC_AUT_NUM):
                line = line.lstrip().replace(
                    JPNIC_AUT_NUM, RPSL_MAPPINGS[JPNIC_AUT_NUM]
                )

            elif line.lstrip().startswith(JPNIC_MNTNER):
                line = line.lstrip().replace(
                    JPNIC_MNTNER, RPSL_MAPPINGS[JPNIC_MNTNER]
                )

            elif line.lstrip().startswith(JPNIC_ROUTE):
                line = line.lstrip().replace(
                    JPNIC_ROUTE, RPSL_MAPPINGS[JPNIC_ROUTE]
                )

                # Check the prefix format is valid
                raw_prefix = line.lstrip(RPSL_MAPPINGS[JPNIC_ROUTE])
                try:
                    raw_prefix = (
                        ".".join(
                            str(int(octet))
                            for octet in raw_prefix.split("/")[0].split(".")
                        )
                        + "/"
                        + raw_prefix.split("/")[1]
                    )
                    ipaddress.IPv4Network(raw_prefix)
                except ValueError:
                    logger.error(f"Invalid JPNIC IPv4 prefix in line: {line}")
                    continue

            elif line.lstrip().startswith(JPNIC_ROUTE6):
                line = line.lstrip().replace(
                    JPNIC_ROUTE6, RPSL_MAPPINGS[JPNIC_ROUTE6]
                )

                try:
                    raw_prefix = line.lstrip(
                        RPSL_MAPPINGS[JPNIC_ROUTE6]
                    ).strip()
                    ipaddress.IPv6Network(raw_prefix)
                except ValueError:
                    logger.error(f"Invalid JPNIC IPv6 prefix in line: {line}")
                    continue

            rpsl_lines.append(line)

        return "\n".join(rpsl_lines).encode("utf-8")

    @staticmethod
    def parse_nicbr(data: bytes) -> bytes:
        """
        NICBR data is in the following format per line:

        ASN|OrgName|OrgID|prefixes

        The prefixes field may be repeated many times separated by vertical bars, each prefix maybe be v4 or v6:

        AS23456|A Company|11.222.333/0001-01|10.0.0.0/8|2001:db8::/32|192.168.0.0/24
        """
        logger.info("Translating NICBR data to RPSL format")

        rpsl_lines: list[str] = []

        lines = data.splitlines()
        for raw_line in lines:
            line = raw_line.decode().strip()
            fields = line.split("|")

            if len(fields) < 4:
                logger.warning(f"Skipping NICBR line without prefixes: {line}")
                continue

            origin = int(fields[0].lower().lstrip("as"))
            org_name = fields[1] if fields[1] else "UNKNOWN"

            for raw_prefix in fields[3:]:
                try:
                    prefix = (
                        ipaddress.IPv4Network(raw_prefix)
                        if "." in raw_prefix
                        else ipaddress.IPv6Network(raw_prefix)
                    )
                except ValueError:
                    logger.error(f"Invalid NICBR prefix in line: {line}")
                    continue

                route_attr = "route" if prefix.version == 4 else "route6"
                rpsl_lines.append(
                    f"{route_attr}: {prefix}\n"
                    f"origin: AS{origin}\n"
                    f"descr: {org_name}\n"
                    f"source: NICBR\n"
                    "\n"
                )

        return "\n".join(rpsl_lines).encode("utf-8")


class IrrParsers(Enum):
    JPIRR = "JPIRR"
    NICBR = "NICBR"
    STANDARD = "STANDARD"

    def parse(self, data: bytes) -> bytes:
        parsers: dict[IrrParsers, Callable[[bytes], bytes]] = {
            IrrParsers.JPIRR: IrrParser.parse_jpirr,
            IrrParsers.NICBR: IrrParser.parse_nicbr,
            IrrParsers.STANDARD: IrrParser.parse_standard,
        }
        return parsers[self](data)


class IrrFile:
    filename: str
    parser: IrrParsers
    url: str

    def __init__(
        self,
        filename: str,
        parser: IrrParsers,
        url: str,
    ) -> None:
        self.filename = filename
        self.parser = parser
        self.url = url

    def get_filename(self) -> str:
        return self.filename

    def get_contents(self) -> str:
        fn = self.get_filename()
        if os.path.splitext(fn)[-1] == ".gz":
            contents = gzip.open(
                fn, "rt", encoding="utf-8", errors="replace"
            ).read()
        else:
            contents = open(
                fn, "rt", encoding="utf-8", errors="replace"
            ).read()
        return contents

    def get_parser(self) -> IrrParsers:
        return self.parser

    def get_url(self) -> str:
        return self.url

    def set_filename(self, filename: str) -> None:
        self.filename = filename


class Fetcher:
    @staticmethod
    def fetch_url(url: str, timeout: int) -> bytes:
        """
        Fetch the raw bytes of a source URL.
        """

        class UpstreamFetchError(Exception):
            """
            Raised when the upstream source could not be retrieved.
            """

        # Force IPv4 resolution, ARIN IPv6 connectivity is unreliable
        import socket

        _orig_getaddrinfo = socket.getaddrinfo

        def _getaddrinfo_ipv4(host, port, family=0, type=0, proto=0, flags=0):  # type: ignore
            return _orig_getaddrinfo(
                host, port, socket.AF_INET, type, proto, flags  # type: ignore
            )

        socket.getaddrinfo = _getaddrinfo_ipv4

        logger.info(f"Fetching URL: {url} with timeout {timeout}s")

        try:
            with urllib.request.urlopen(url, timeout=timeout) as response:
                return response.read()
        except (urllib.error.URLError, OSError, ValueError) as e:
            raise UpstreamFetchError(f"Failed to fetch '{url}': {e}") from e

        socket.getaddrinfo = _orig_getaddrinfo

    @staticmethod
    def fetch_and_translate(
        irr_file: IrrFile,
        timeout: int,
    ) -> bytes:
        """
        Fetch an IRR DB file, decompress it (if gzipped), transform it, and re-compress it.
        """

        logger.info(
            f"Going to fetch and translate {irr_file.get_url()} with timeout {timeout}s"
        )

        raw = Fetcher.fetch_url(irr_file.get_url(), timeout=timeout)

        if irr_file.get_url().endswith(".gz"):
            logger.info(f"Decompressing gzip data from {irr_file.get_url()}")
            decompressed = gzip.decompress(raw)
        else:
            decompressed = raw

        decompressed = irr_file.get_parser().parse(decompressed)

        if irr_file.get_url().endswith(".gz"):
            logger.info(
                f"Returning compressed data for URL: {irr_file.get_url()}"
            )
            return gzip.compress(decompressed)

        logger.info(
            f"Returning uncompressed data for URL: {irr_file.get_url()}"
        )
        return decompressed


def main() -> None:
    DATA_DIR = os.path.join(os.path.dirname(__file__), "../data/packed/")
    IRR_FILES = [
        IrrFile(
            os.path.join(DATA_DIR, os.path.basename(url)),
            IrrParsers.STANDARD,
            url,
        )
        for url in [
            "https://ftp.afrinic.net/dbase/afrinic.db.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.as-set.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.aut-num.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.inet6num.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.inetnum.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.mntner.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.route-set.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.route.gz",
            "https://ftp.apnic.net/apnic/whois/apnic.db.route6.gz",
            "https://ftp.arin.net/pub/rr/arin.db.gz",
            "https://ftp.apnic.net/apnic/dbase/data/jpnic.db.gz",
            "https://ftp.apnic.net/apnic/dbase/data/krnic.db.gz",
            "https://irr.lacnic.net/lacnic.db.gz",
            # "https://rr1.ntt.net/nttcomRR/nttcom.db.gz",
            "ftp://ftp.radb.net/radb/dbase/radb.db.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.as-set.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.aut-num.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.inet6num.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.inetnum.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.mntner.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.route-set.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.route.gz",
            "https://ftp.ripe.net/ripe/dbase/split/ripe.db.route6.gz",
            "https://ftp.bgp.net.br/tc.db.gz",
            "https://ftp.apnic.net/apnic/dbase/data/twnic.db.gz",
        ]
    ] + [
        IrrFile(
            os.path.join(DATA_DIR, "nicbr-asn-blk-latest.txt"),
            IrrParsers.NICBR,
            "https://ftp.registro.br/pub/numeracao/origin/nicbr-asn-blk-latest.txt",
        )
    ]

    def download(irr_file: IrrFile) -> None:
        logger.info(f"IRR file: {irr_file.get_filename()}")

        if os.path.exists(irr_file.get_filename()):
            logger.info(
                f"File {irr_file.get_filename()} already exists, skipping download\n"
            )
            return

        data = Fetcher.fetch_and_translate(
            irr_file,
            timeout=300,
        )

        with open(irr_file.get_filename(), "wb") as f:
            f.write(data)
        logger.info(f"Successfully wrote to {irr_file.get_filename()}\n")

    if len(sys.argv) == 2 and sys.argv[1] == "-j":
        IRR_FILES.append(
            IrrFile(
                os.path.join(DATA_DIR, "jpirr.db.gz"),
                IrrParsers.JPIRR,
                "https://ftp.nic.ad.jp/jpirr/jpirr.db.gz",
            )
        )
    else:
        IRR_FILES.append(
            IrrFile(
                os.path.join(DATA_DIR, "jpirr.db.gz"),
                IrrParsers.STANDARD,
                "https://ftp.nic.ad.jp/jpirr/jpirr.db.gz",
            )
        )

    if not os.path.exists(DATA_DIR):
        os.makedirs(DATA_DIR)
        logger.info(f"Created data directory: {DATA_DIR}")

    max_workers = max(1, (os.cpu_count() or 1) - 1)
    logger.info(f"Downloading with {max_workers} threads")

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(download, irr_file) for irr_file in IRR_FILES
        ]
        for future in as_completed(futures):
            # Re-raise any exception from the worker thread
            future.result()

    logger.info("All files downloaded")


if __name__ == "__main__":
    main()
