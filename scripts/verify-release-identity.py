#!/usr/bin/env python3
"""Compare runtime source while permitting two explicit additional notices.

This checks files, not desktop interaction or saved-file compatibility. The
previous directory must be the preserved source of the desktop-tested build.
Only the named libdeflate notice files may be added; existing files must remain
byte-identical. Added notices and their hashes are recorded in the JSON result.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import json

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--previous", type=Path, required=True)
parser.add_argument("--current", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()

ADDITIONAL_NOTICE_FILES = {
    "inst/third-party/LICENSE.libdeflate",
    "inst/third-party/README.txt",
}


def runtime_files(root):
    paths = {"NAMESPACE": root / "NAMESPACE"}
    for directory in ("R", "inst"):
        for path in (root / directory).rglob("*"):
            if path.is_file() and path.name != ".DS_Store":
                if path.is_symlink():
                    raise ValueError("Runtime source must not contain symlinks")
                paths[path.relative_to(root).as_posix()] = path
    return paths


def dcf(path):
    fields = {}
    current = None
    for line in path.read_text().splitlines():
        if line[:1].isspace() and current:
            fields[current] += " " + line.strip()
        elif ":" in line:
            current, value = line.split(":", 1)
            fields[current] = value.strip()
    return fields


previous = runtime_files(args.previous)
current = runtime_files(args.current)
added = set(current) - set(previous)
removed = set(previous) - set(current)
if removed or added - ADDITIONAL_NOTICE_FILES:
    raise ValueError("Runtime file lists differ beyond the permitted additional notices")
added_notices = [
    {"file": name, "publicSHA256": hashlib.sha256(current[name].read_bytes()).hexdigest()}
    for name in sorted(added)
]
rows = []
for name in sorted(previous):
    old = hashlib.sha256(previous[name].read_bytes()).hexdigest()
    new = hashlib.sha256(current[name].read_bytes()).hexdigest()
    if old != new:
        raise ValueError("Runtime source differs: " + name)
    rows.append({"file": name, "developmentSHA256": old, "publicSHA256": new, "identical": "TRUE"})
old_description = dcf(args.previous / "DESCRIPTION")
new_description = dcf(args.current / "DESCRIPTION")
old_version = old_description.pop("Version")
new_version = new_description.pop("Version")
if old_description != new_description:
    raise ValueError("DESCRIPTION fields other than Version differ")
args.output.parent.mkdir(parents=True, exist_ok=True)
with args.output.open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps({"status": "PASS", "developmentVersion": old_version,
                  "publicVersion": new_version, "identicalRuntimeFiles": len(rows),
                  "addedNoticeFiles": added_notices,
                  "descriptionChanges": ["Version"],
                  "scope": "Existing source-file identity and explicit additional notices only; dependency binaries, desktop interaction and saved-file compatibility were not verified by this comparison."}, indent=2))
