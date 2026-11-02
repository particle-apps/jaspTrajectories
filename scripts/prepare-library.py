#!/usr/bin/env python3
"""Restore the checked macOS/arm64 dependency lock, never another R library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def tree_hash(root):
    # Deliberately ignores timestamps, owner and modes; hashes paths and contents.
    digest = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        if path.name == '.DS_Store':
            continue
        relative = path.relative_to(root).as_posix().encode()
        if path.is_symlink():
            digest.update(b'L\0' + relative + b'\0' + os.readlink(path).encode() + b'\0')
        elif path.is_file():
            digest.update(b'F\0' + relative + b'\0' + sha256(path).encode() + b'\0')
    return digest.hexdigest()


def dcf(path):
    result, field = {}, None
    for line in path.read_text().splitlines():
        if line[:1].isspace() and field:
            result[field] += ' ' + line.strip()
        elif ':' in line:
            field, value = line.split(':', 1)
            result[field] = value.strip()
    return result


def unpack(archive, destination, name):
    with tarfile.open(archive, 'r:gz') as source:
        for member in source.getmembers():
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != name:
                raise RuntimeError('Unexpected archive path: ' + member.name)
            if member.isdir():
                (destination / path).mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target = destination / path
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as reader, target.open('wb') as writer:
                    shutil.copyfileobj(reader, writer)
                target.chmod(member.mode & 0o777)
            else:
                raise RuntimeError('Archive links or special files are not supported: ' + member.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--jasp', type=Path, default=Path('/Applications/JASP.app'))
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--lock', type=Path, default=Path(__file__).with_name('dependencies-macos-arm64.lock.json'))
    parser.add_argument('--offline', action='store_true', help='Require cached official CRAN archives')
    args = parser.parse_args()
    lock = json.loads(args.lock.read_text())
    args.jasp = args.jasp.resolve()
    args.library = args.library.resolve()
    args.cache = args.cache.resolve()
    info = plistlib.loads((args.jasp / 'Contents/Info.plist').read_bytes())
    if info['CFBundleVersion'] != lock['environment']['jasp_bundle_version']:
        raise RuntimeError('JASP version differs from the tested dependency lock; do not silently substitute it.')
    r_home = args.jasp / lock['environment']['r_home']
    if sha256(r_home / 'bin/exec/R') != lock['environment']['r_executable_sha256']:
        raise RuntimeError('Embedded R executable differs from the tested lock.')
    tool = args.jasp / lock['environment']['bundle_tool_path']
    if tree_hash(tool) != lock['environment']['bundle_tool_tree_sha256']:
        raise RuntimeError('JASP bundle tool dependencies differ from the tested lock.')
    if args.library.exists() and any(args.library.iterdir()):
        raise RuntimeError('The target library must be empty. Choose a new build directory.')
    args.library.mkdir(parents=True, exist_ok=True)
    args.cache.mkdir(parents=True, exist_ok=True)
    record = []
    with tempfile.TemporaryDirectory(prefix='trajectories-deps-') as temporary:
        temporary = Path(temporary)
        for package in lock['packages']:
            name = package['name']
            if package['source'] == 'cran-binary':
                archive = args.cache / package['archive']
                if not archive.exists():
                    if args.offline:
                        raise RuntimeError('Missing pinned archive: ' + str(archive))
                    partial = archive.with_suffix('.download')
                    try:
                        with urllib.request.urlopen(package['url'], timeout=60) as response, partial.open('wb') as output:
                            shutil.copyfileobj(response, output)
                        if sha256(partial) != package['archive_sha256']:
                            raise RuntimeError('Downloaded archive checksum mismatch: ' + name)
                        partial.replace(archive)
                    finally:
                        partial.unlink(missing_ok=True)
                if sha256(archive) != package['archive_sha256']:
                    raise RuntimeError('Cached archive checksum mismatch: ' + name)
                unpack(archive, temporary, name)
                source = temporary / name
            else:
                source = args.jasp / package['path']
            if tree_hash(source) != package['tree_sha256']:
                raise RuntimeError('Dependency content checksum mismatch: ' + name)
            metadata = dcf(source / 'DESCRIPTION')
            if metadata.get('Package') != name or metadata.get('Version') != package['version']:
                raise RuntimeError('Dependency package/version mismatch: ' + name)
            if package['install']:
                shutil.copytree(source, args.library / name, symlinks=True)
                if tree_hash(args.library / name) != package['tree_sha256']:
                    raise RuntimeError('Copied dependency checksum mismatch: ' + name)
            record.append({'name': name, 'version': package['version'], 'source': package['source'],
                           'installed_in_private_library': package['install'],
                           'tree_sha256': package['tree_sha256']})
    # Verify the actual R environment and package versions without user/site paths.
    environment = os.environ.copy()
    environment.update(JASP_R_HOME=str(r_home), R_HOME=str(r_home), R_LIBS='',
                       R_LIBS_USER=str(args.library), R_LIBS_SITE=str(args.library.parent / 'empty-site'))
    expression = '''
      stopifnot(as.character(getRversion()) == "%s", grepl("aarch64", R.version$platform))
      paths <- normalizePath(.libPaths(), mustWork=TRUE)
      allowed <- normalizePath(c(Sys.getenv("R_LIBS_USER"), file.path(R.home(), "library")))
      stopifnot(all(paths %%in%% allowed))
      cat("R version:", as.character(getRversion()), "\\nLibrary paths:", paste(paths, collapse="; "), "\\n")
    ''' % lock['environment']['r_version']
    subprocess.run([str(r_home / 'bin/R'), '--vanilla', '--slave', '-e', expression],
                   env=environment, check=True)
    provenance = {'lock_sha256': sha256(args.lock), 'environment': lock['environment'],
                  'packages': record, 'system_or_user_R_libraries_used': False}
    (args.library.parent / 'dependency-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print('Verified %d locked packages; restored %d into an empty private library.' %
          (len(record), sum(x['installed_in_private_library'] for x in record)))


if __name__ == '__main__':
    main()
