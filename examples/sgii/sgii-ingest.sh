#!/usr/bin/env bash 

# Uses SGII to generates a sitemap XML file from a JSONL input of web objects

# License: MIT (code) and CC BY 4.0 
# (c) scaleoutSean, https://github.com/scaleoutsean, (c) 2026

# Note:
# - Pay attention to security and read README
# - base-url is where the data will be served to bots, not StorageGRID S3 API endpoint
# - extensions specify which file types to include in the sitemap. "" is required for all
# - Separately, use ACLs on the bucket to deny access to other paths

```sh
SITEMAP="$(python3 -c 'import datetime, time, uuid; print("snapshot-" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + str(time.time_ns()) + "-" + uuid.uuid4().hex[:12] + ".xml")')"

python3 - \
  --input web-objects.jsonl \
  --base-url https://proj1a2b3c.public.company.com/ \
  --extensions .html,.htm \
  --output "$SITEMAP" <<'PY'
import argparse
import datetime
import json
from urllib.parse import quote
import xml.etree.ElementTree as ET

def utc_time(value):
  parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
  if parsed.tzinfo is None:
    raise ValueError("timestamps must include a UTC offset or Z")
  return parsed.astimezone(datetime.timezone.utc)

parser = argparse.ArgumentParser()
parser.add_argument("--input", required=True)
parser.add_argument("--base-url", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--extensions", default=".html,.htm")
parser.add_argument("--since", type=utc_time)
parser.add_argument("--before", type=utc_time)
args = parser.parse_args()
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
with open(args.output, "xb") as destination:
  destination.write(xml)
print(args.output)
PY
```
