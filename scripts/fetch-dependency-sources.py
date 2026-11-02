#!/usr/bin/env python3
"""Fetch or verify the preserved dependency sources; never install or run them."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import urllib.request


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(path, entry):
    if sha256(path) != entry["sha256"]:
        raise ValueError("SHA-256 mismatch: " + entry["archive"])
    if entry.get("description_path"):
        with tarfile.open(path, "r:*") as archive:
            member = archive.getmember(entry["description_path"])
            if not member.isfile():
                raise ValueError("Package DESCRIPTION is not a regular file")
            fields = {}
            for line in archive.extractfile(member).read().decode("utf-8").splitlines():
                if line and not line[:1].isspace() and ":" in line:
                    key, value = line.split(":", 1)
                    fields[key] = value.strip()
            if (fields.get("Package"), fields.get("Version")) != (entry["name"], entry["version"]):
                raise ValueError("Package/version mismatch: " + entry["archive"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True, help="Extracted source bundle root, or download destination")
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("dependency-sources.lock.json"))
    parser.add_argument("--verify-only", action="store_true", help="Check existing files without network access")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    destination = args.directory.resolve()
    for entry in manifest["archives"]:
        relative = PurePosixPath(entry["archive"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unsafe archive path in manifest")
        target = destination / relative
        if not target.resolve().is_relative_to(destination):
            raise ValueError("Archive path escapes destination")
        if target.exists():
            verify(target, entry)
        elif args.verify_only:
            raise FileNotFoundError(target)
        else:
            if not entry["url"].startswith("https://"):
                raise ValueError("Source URL must use HTTPS")
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(target.suffix + ".part")
            try:
                request = urllib.request.Request(entry["url"], headers={"User-Agent": "jaspTrajectories-source-restore/0.1.0"})
                with urllib.request.urlopen(request, timeout=60) as response:
                    with temporary.open("wb") as output:
                        while True:
                            block = response.read(1024 * 1024)
                            if not block:
                                break
                            output.write(block)
                verify(temporary, entry)
                temporary.replace(target)
            finally:
                temporary.unlink(missing_ok=True)
        print("VERIFIED", entry["archive"], flush=True)
    print("Verified", len(manifest["archives"]), "source archives. No packages installed or source code executed.")
    print("Verification establishes archived file identity; see DEPENDENCY-SOURCES.md for build-provenance limitations.")


if __name__ == "__main__":
    main()
