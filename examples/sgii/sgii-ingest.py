#!/usr/bin/env python3

# License: MIT (code) and CC BY 4.0
# (c) scaleoutSean, https://github.com/scaleoutsean, (c) 2026

import argparse
import datetime
import json
import time
import uuid
from urllib.parse import quote
import xml.etree.ElementTree as ET


def utc_time(value):
    parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamps must include a UTC offset or Z")
    return parsed.astimezone(datetime.timezone.utc)


def default_filename():
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"snapshot-{timestamp}-{time.time_ns()}-{uuid.uuid4().hex[:12]}.xml"


def main():
    parser = argparse.ArgumentParser(description="Create a sitemap from SGII query objects JSONL output.")
    parser.add_argument("--input", required=True, help="JSONL exported with query objects --latest-only")
    parser.add_argument("--base-url", required=True, help="Public gateway URL, not the StorageGRID API endpoint")
    parser.add_argument("--output", help="Output XML path; defaults to a unique snapshot-*.xml filename")
    parser.add_argument("--extensions", default=".html,.htm", help='Comma-separated suffixes; default: .html,.htm; use "" for all objects')
    parser.add_argument("--since", type=utc_time, help="Inclusive last-modified timestamp with UTC offset or Z")
    parser.add_argument("--before", type=utc_time, help="Exclusive last-modified timestamp with UTC offset or Z")
    args = parser.parse_args()
    output = args.output if args.output is not None else default_filename()
    extensions = tuple(item.strip().lower() for item in args.extensions.split(",") if item.strip())
    namespace = "http://www.sitemaps.org/schemas/sitemap/0.9"
    ET.register_namespace("", namespace)
    root = ET.Element("{" + namespace + "}urlset")
    seen = set()
    with open(args.input, encoding="utf-8") as records:
        for line in records:
            record = json.loads(line)
            key = record["key"]
            modified = utc_time(record["last_modified"])
            if extensions and not key.lower().endswith(extensions):
                continue
            if args.since and modified < args.since:
                continue
            if args.before and modified >= args.before:
                continue
            location = args.base_url.rstrip("/") + "/" + quote(key, safe="/")
            if location in seen:
                continue
            if len(location) > 2048:
                raise SystemExit("URL exceeds the sitemap 2,048-character limit")
            seen.add(location)
            if len(seen) > 50000:
                raise SystemExit("Split into sitemaps of at most 50,000 URLs and publish a sitemap index")
            entry = ET.SubElement(root, "{" + namespace + "}url")
            ET.SubElement(entry, "{" + namespace + "}loc").text = location
            ET.SubElement(entry, "{" + namespace + "}lastmod").text = modified.isoformat().replace("+00:00", "Z")
    xml = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    if len(xml) > 50 * 1024 * 1024:
        raise SystemExit("Split into sitemaps of at most 50 MB uncompressed and publish a sitemap index")
    with open(output, "xb") as destination:
        destination.write(xml)
    print(output)


if __name__ == "__main__":
    main()