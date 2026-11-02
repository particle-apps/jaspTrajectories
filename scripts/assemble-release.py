#!/usr/bin/env python3
"""Assemble public artifacts after the finalized validation report and desktop evidence.

This script never installs a module, edits saved JASP files or includes a general
build library. Run only after current check statuses and the report are finalized;
historical desktop evidence must remain explicitly identified as historical.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import math
import os
import sqlite3
import tempfile
import shutil
import tarfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--assemble", action="store_true", help="Write the finalized archives and checksums")
args = parser.parse_args()
module = Path(os.environ.get("TRAJECTORIES_MODULE_DIR", Path(__file__).resolve().parents[1])).resolve()
project = Path(os.environ.get("TRAJECTORIES_PROJECT_DIR", module if (module / "validation").is_dir() else module.parent)).resolve()
validation = Path(os.environ.get("TRAJECTORIES_VALIDATION_DIR", project / "validation")).resolve()
dist = Path(os.environ.get("TRAJECTORIES_DIST_DIR", project / "dist")).resolve()
build = Path(os.environ.get("TRAJECTORIES_BUILD_DIR", project / "build")).resolve()
cache = Path(os.environ.get("TRAJECTORIES_CACHE_DIR", project / "build/downloads")).resolve()


def sha256(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def dcf(text):
    fields = {}
    field = None
    for line in text.splitlines():
        if line[:1].isspace() and field:
            fields[field] += " " + line.strip()
        elif ":" in line:
            field, value = line.split(":", 1)
            fields[field] = value.strip()
    return fields


version = dcf((module / "DESCRIPTION").read_text())["Version"]
prefix = "jaspTrajectories"
source_tar = build / ("jaspTrajectories_" + version + ".tar.gz")
installer = dist / "jaspTrajectories.JASPModule"
manifest_path = dist / "jaspTrajectories_manifest.json"
manifest = json.loads(manifest_path.read_text())
assert manifest["version"] == [[int(x) for x in version.split(".")]]
assert manifest["complete"] is True
installer_sha = sha256(installer)
source_build = json.loads((build / "source-build-provenance.json").read_text())
dependency_provenance = json.loads((build / "dependency-provenance.json").read_text())
assert dependency_provenance["source_build_provenance_sha256"] == sha256(build / "source-build-provenance.json")
assert dependency_provenance["libdeflate_notice_sha256"] == sha256(module / "inst/third-party/LICENSE.libdeflate")
assert (validation / "evidence/release/source-build-provenance.json").read_bytes() == (build / "source-build-provenance.json").read_bytes()
assert (validation / "evidence/release/dependency-provenance.json").read_bytes() == (build / "dependency-provenance.json").read_bytes()
dependency_sources_name = "jaspTrajectories-dependency-sources-" + version + ".zip"
dependency_sources = dist / dependency_sources_name
source_lock = json.loads((module / "scripts/dependency-sources.lock.json").read_text())
assert source_lock["installer_sha256"] == installer_sha, "Dependency sources refer to a different installer"
assert source_lock["binary_dependency_lock_sha256"] == sha256(module / "scripts/dependencies-macos-arm64.lock.json")
with zipfile.ZipFile(dependency_sources) as archive:
    assert archive.testzip() is None, dependency_sources_name
    source_prefix = "jaspTrajectories-dependency-sources-" + version + "/"
    packaged_source_lock = json.loads(archive.read(source_prefix + "SOURCE-MANIFEST.json"))
    assert packaged_source_lock == source_lock, "Dependency source index differs from the repository"
    for entry in source_lock["archives"]:
        with archive.open(source_prefix + entry["archive"]) as stream:
            digest = hashlib.sha256()
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        assert digest.hexdigest() == entry["sha256"], entry["archive"]

# A stale report cannot be packaged under a newer release label.
metadata = json.loads((validation / "results/run-metadata.json").read_text())
assert metadata["moduleVersion"] == version
assert not (validation / "RUN-FAILED.txt").exists()
assert (validation / "START-HERE.html").is_file()
with (validation / "results/test-stages.csv").open() as stream:
    stages = list(csv.DictReader(stream))
assert len(stages) == 8 and all(r["status"] == "PASS" and r["exitCode"] == "0" for r in stages)
source_fingerprint = sha256(validation / "results/source-file-hashes.csv")
for name in ("release-checks.csv", "desktop-checks.csv"):
    with (validation / "results" / name).open() as stream:
        evidence = list(csv.DictReader(stream))
    assert evidence, name
    for row in evidence:
        assert row["moduleVersion"] == version and row["sourceFingerprint"] == source_fingerprint, name
        if row.get("installerSHA256"):
            assert row["installerSHA256"] == installer_sha, name
        if row.get("evidence"):
            assert (validation / row["evidence"]).is_file(), row["evidence"]

excluded = {".DS_Store", "__pycache__", ".git", ".agents", ".codex"}

def public_files(folder, module_tree=False):
    files = []
    generated = {"build", "dist", "archive", "validation", "release-assets"}
    for current, directories, names in os.walk(folder):
        current = Path(current)
        directories[:] = sorted(name for name in directories
                                if name not in excluded and not (module_tree and
                                (name in generated or name.startswith("github-release-v") or name.endswith(".Rcheck"))))
        for name in sorted(names):
            path = current / name
            if name in excluded or name.endswith((".pyc", ".JASPModule")):
                continue
            assert not path.is_symlink(), path
            files.append(path)
    return sorted(files)


module_files = public_files(module, module_tree=True)
validation_files = public_files(validation)
manifest_entries = {}
for line in (validation / "SHA256SUMS.txt").read_text().splitlines():
    digest, name = line.split("  ", 1)
    manifest_entries[name] = digest
for path in validation_files:
    relative = str(path.relative_to(validation))
    if relative == "SHA256SUMS.txt":
        continue
    assert manifest_entries.get(relative) == sha256(path), "Regenerate validation report/checksums: " + relative

# Only the four documented public reference CSVs are accepted as validation input.
assert {p.name for p in (validation / "data").iterdir() if p.is_file()} == {
    "lcmm-continuous.csv", "lcmm-continuous-missing.csv", "lcmm-ordinal.csv", "paquid-ordinal.csv"}
# Saved desktop examples must contain exactly a documented public CSV. JASP's
# autosave display name can change to the .jasp filename after reopening, so use
# the database import path and verify every actual data cell rather than that label.
allowed_csvs = {p.name for p in (validation / "data").iterdir() if p.is_file()}
for path in validation_files:
    if path.suffix != ".jasp":
        continue
    before = sha256(path)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, path.name
        with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as temporary:
            temporary.write(archive.read("internal.sqlite"))
            temporary_path = temporary.name
    try:
        connection = sqlite3.connect("file:" + temporary_path + "?mode=ro", uri=True)
        datasets = list(connection.execute("SELECT id,dataFilePath FROM DataSets"))
        assert len(datasets) == 1, path.name
        dataset_id, source_path = datasets[0]
        source_name = Path(source_path).name
        assert source_name in allowed_csvs, path.name
        columns = list(connection.execute("SELECT id,name FROM Columns ORDER BY colIdx"))
        assert [row[1] for row in columns] == ["subject", "time", "outcome"], path.name
        selected = ",".join('"Column_' + str(int(row[0])) + '"' for row in columns)
        records = list(connection.execute("SELECT " + selected + " FROM DataSet_" + str(int(dataset_id)) + " ORDER BY rowNumber"))
        with (validation / "data" / source_name).open() as stream:
            reference = list(csv.DictReader(stream))
        assert len(records) == len(reference), path.name
        for actual, expected in zip(records, reference):
            for value, (_, column) in zip(actual, columns):
                if expected[column] == "":
                    assert value is None or math.isnan(value), path.name
                else:
                    assert value is not None and abs(float(value) - float(expected[column])) < 1e-12, path.name
        connection.close()
    finally:
        os.unlink(temporary_path)
    assert sha256(path) == before, path.name

# The previously checked R source tar must still agree with the final package files.
with tarfile.open(source_tar) as archive:
    packaged_description = dcf(archive.extractfile("jaspTrajectories/DESCRIPTION").read().decode())
    for field, value in dcf((module / "DESCRIPTION").read_text()).items():
        assert packaged_description.get(field) == value, "Stale source tar DESCRIPTION: " + field
    for member in archive.getmembers():
        relative = Path(member.name).relative_to("jaspTrajectories")
        if member.isfile() and (relative.parts[0] in ("R", "inst", "man") or str(relative) in ("NAMESPACE", "NEWS.md")):
            assert archive.extractfile(member).read() == (module / relative).read_bytes(), relative

lock_path = module / "scripts/dependencies-macos-arm64.lock.json"
lock = json.loads(lock_path.read_text())
inputs = []
for package in lock["packages"]:
    if package.get("source") == "cran-binary":
        cached = cache / package["archive"]
        assert sha256(cached) == package["archive_sha256"], cached.name
        inputs.append(cached)
assert len(inputs) == 2

if not args.assemble:
    print("Preflight passed. No archives written. Run with --assemble only after release sign-off.")
    raise SystemExit(0)


def make_zip(destination, entries, root_prefix=""):
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path, name in entries:
            archive.write(path, root_prefix + name)
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None, destination.name
        for name in archive.namelist():
            assert "/archive/" not in name and "/library/" not in name
    print("Verified", destination.name)


shutil.copy2(source_tar, dist / source_tar.name)
module_entries = [(path, path.relative_to(module).as_posix()) for path in module_files]
validation_entries = [(path, "validation/" + path.relative_to(validation).as_posix()) for path in validation_files]
make_zip(dist / "jaspTrajectories-source.zip", module_entries, "jaspTrajectories/")
make_zip(dist / "jaspTrajectories-validation.zip", validation_entries)
combined_name = "jaspTrajectories-public-beta-" + version + "-source-validation.zip"
make_zip(dist / combined_name, module_entries + validation_entries, prefix + "/")
inputs_name = "jaspTrajectories-build-inputs-" + version + ".zip"
with zipfile.ZipFile(dist / inputs_name, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in inputs:
        archive.write(path, prefix + "/build/downloads/" + path.name)
    archive.write(lock_path, prefix + "/scripts/" + lock_path.name)
    instructions = (
        "# Preserved public-beta build inputs\n\n"
        "Extract this archive beside the combined source/validation archive: both use the same project folder.\n"
        "The two unchanged official CRAN binaries populate build/downloads/ and are verified against the included lock.\n"
        "The matching JASP Apple Silicon application is still required and is not included here.\n"
        "From that extracted package root, run sh scripts/build-macos.sh; see BUILDING.md for the exact app version and compiler environment.\n"
        "The builder replaces jaspBase with a pinned source build. Extract the dependency-source ZIP and set TRAJECTORIES_SOURCE_CACHE_DIR to its root for an offline source build.\n"
        "These are dependency inputs, not a JASP installer. The installer is jaspTrajectories.JASPModule.\n"
        "Corresponding-source materials are supplied separately in jaspTrajectories-dependency-sources-" + version + ".zip; read DEPENDENCY-SOURCES.md for coverage and remaining provenance limits.\n"
        "No general build library, user data or archived implementation is included.\n"
    )
    archive.writestr(prefix + "/BUILD-INPUTS.md", instructions)
with zipfile.ZipFile(dist / inputs_name) as archive:
    assert archive.testzip() is None
print("Verified", inputs_name)

current = ["jaspTrajectories.JASPModule", "jaspTrajectories_manifest.json", source_tar.name,
           "jaspTrajectories-source.zip", "jaspTrajectories-validation.zip", combined_name, inputs_name,
           dependency_sources_name]
(dist / "PUBLIC-BETA-FILES.txt").write_text(
    "Trajectories for JASP " + version + " public beta\n\n" + "\n".join(current) +
    "\n\nOnly the files above are current public-beta deliverables. Older numbered source archives are historical.\n"
    "The R source tar is the exact checked package; repository/test/validation documentation is excluded by R build rules.\n"
    "The source ZIP includes module documentation and build/test scripts; the combined ZIP also includes public validation materials.\n")
checksums = []
for path in sorted(dist.iterdir()):
    if path.is_file() and path.name not in ("SHA256SUMS.txt", ".DS_Store"):
        checksums.append(sha256(path) + "  " + path.name)
(dist / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n")
assert sha256(installer) == installer_sha
print("Assembly complete; installer unchanged; distribution SHA-256 manifest updated.")
