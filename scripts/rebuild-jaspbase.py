#!/usr/bin/env python3
"""Rebuild jaspBase with pinned Common sources before creating the JASP bundle.

The dependency library must already be restored. Compilation uses a temporary
copy of Rcpp with matching source headers; the final Rcpp package is unchanged.
The original jaspBase is replaced only after the staged build and native load
check pass. No upstream source file is edited.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import tarfile
import urllib.request


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def tree_hash(root):
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


def file_hashes(root):
    return {path.relative_to(root).as_posix(): sha256(path)
            for path in sorted(root.rglob('*')) if path.is_file()}


def dcf(path):
    result, field = {}, None
    for line in path.read_text().splitlines():
        if line[:1].isspace() and field:
            result[field] += ' ' + line.strip()
        elif ':' in line:
            field, value = line.split(':', 1)
            result[field] = value.strip()
    return result


def capture(command, env=None):
    return subprocess.check_output(command, env=env, text=True).strip()


def fetch(entry, cache, offline):
    relative = PurePosixPath(entry['archive'])
    if relative.is_absolute() or '..' in relative.parts or not relative.parts:
        raise ValueError('Unsafe source-cache path')
    target = cache / relative
    if not target.resolve().is_relative_to(cache):
        raise ValueError('Source-cache path escapes cache')
    if not target.exists():
        if offline:
            raise FileNotFoundError('Missing pinned source archive: ' + str(target))
        if not entry['url'].startswith('https://'):
            raise ValueError('Source URL must use HTTPS')
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_name(target.name + '.part')
        if partial.exists() or partial.is_symlink():
            raise FileExistsError('Remove incomplete download before retrying: ' + str(partial))
        try:
            request = urllib.request.Request(entry['url'], headers={'User-Agent': 'jaspTrajectories-pinned-source-build/0.1.0'})
            with urllib.request.urlopen(request, timeout=60) as response, partial.open('xb') as output:
                shutil.copyfileobj(response, output)
            if sha256(partial) != entry['sha256']:
                raise ValueError('Source archive checksum mismatch: ' + entry['archive'])
            partial.replace(target)
        finally:
            partial.unlink(missing_ok=True)
    if sha256(target) != entry['sha256']:
        raise ValueError('Source archive checksum mismatch: ' + entry['archive'])
    return target


def extract_subtree(archive_path, prefix, destination):
    count = 0
    with tarfile.open(archive_path, 'r:gz') as archive:
        for member in archive.getmembers():
            if not member.name.startswith(prefix + '/'):
                continue
            relative = PurePosixPath(member.name[len(prefix) + 1:])
            if not relative.parts:
                continue
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe source archive member: ' + member.name)
            target = destination / relative
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output)
                target.chmod(member.mode & 0o777)
                count += 1
            else:
                raise ValueError('Source archive links and special files are not accepted: ' + member.name)
    if not count:
        raise ValueError('Source archive subtree is empty: ' + prefix)
    return count


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True, help='Dependency-source ZIP root, or source archive download cache')
    parser.add_argument('--jasp', type=Path, default=Path('/Applications/JASP.app'))
    parser.add_argument('--lock', type=Path, default=Path(__file__).with_name('jaspbase-source-build.lock.json'))
    parser.add_argument('--workdir', type=Path, help='Fresh build directory; defaults beside the private library')
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    lock = json.loads(args.lock.read_text())
    library = args.library.resolve()
    cache = args.cache.resolve()
    app = args.jasp.resolve()
    work = (args.workdir or library.parent / 'jaspbase-source-build').resolve()
    if work.exists() and any(work.iterdir()):
        raise ValueError('The source build directory must be empty; choose --workdir with a new path')
    if work == library or work.is_relative_to(library):
        raise ValueError('Keep source-build work files outside the final package library')
    for name, version in (('jaspBase', lock['jaspbase_version']), ('Rcpp', lock['rcpp_version'])):
        metadata = dcf(library / name / 'DESCRIPTION')
        if metadata.get('Package') != name or metadata.get('Version') != version:
            raise ValueError('Restored dependency version mismatch: ' + name)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleVersion'] != lock['jasp_bundle_version']:
        raise ValueError('JASP app differs from the source-build target')
    r_home = app / lock['r_home']
    if sha256(r_home / 'bin/exec/R') != lock['r_executable_sha256']:
        raise ValueError('Embedded R executable differs from the source-build target')
    # Verify every archive before extracting or running any upstream script.
    inputs = {entry['name']: fetch(entry, cache, args.offline) for entry in lock['source_archives']}
    original_rcpp_hash = tree_hash(library / 'Rcpp')
    original_jaspbase_hash = tree_hash(library / 'jaspBase')
    for directory in ('source/jaspBase', 'library', 'build-library', 'empty-site'):
        (work / directory).mkdir(parents=True, exist_ok=True)
    source = work / 'source/jaspBase'
    extract_subtree(inputs['jaspBase'], lock['jaspbase_archive_root'], source)
    original_source_hashes = file_hashes(source)
    common = source / 'inst/include/Common'
    extract_subtree(inputs['jasp-desktop'], lock['common_archive_root'], common)
    common_hashes = file_hashes(common)
    if common_hashes != lock['common_files_sha256']:
        raise ValueError('Extracted Common files differ from the pinned source record')
    build_rcpp = work / 'build-library/Rcpp'
    shutil.copytree(library / 'Rcpp', build_rcpp, symlinks=True)
    # The distributed Rcpp may omit headers. Always compile against those from
    # the verified matching source, leaving the final dependency untouched.
    if (build_rcpp / 'include').is_symlink():
        (build_rcpp / 'include').unlink()
    elif (build_rcpp / 'include').exists():
        shutil.rmtree(build_rcpp / 'include')
    extract_subtree(inputs['Rcpp'], lock['rcpp_headers_archive_root'], build_rcpp / 'include')
    if not (build_rcpp / 'include/Rcpp.h').is_file():
        raise ValueError('Missing Rcpp source headers')
    if any(sha256(source / name) != digest for name, digest in original_source_hashes.items()):
        raise ValueError('An original jaspBase source file changed during preparation')

    compiler = capture(['/usr/bin/xcrun', '--find', 'clang++'])
    sdk = capture(['/usr/bin/xcrun', '--show-sdk-path'])
    sdk_version = capture(['/usr/bin/xcrun', '--show-sdk-version'])
    makevars = work / 'Makevars'
    makevars.write_text('CXX20 = "' + compiler + '" -arch arm64 -mmacosx-version-min=11.0 -isysroot "' + sdk + '"\n'
                       'CXX20FLAGS = -falign-functions=64 -Wall -g -O2\nMAKEFLAGS = -j2\n')
    env = os.environ.copy()
    env.update(JASP_R_HOME=str(r_home), R_HOME=str(r_home), R_LIBS='',
               R_LIBS_USER=os.pathsep.join(map(str, [work / 'library', work / 'build-library', library])),
               R_LIBS_SITE=str(work / 'empty-site'),
               R_ENVIRON_USER='/dev/null', R_ENVIRON='/dev/null',
               R_PROFILE_USER='/dev/null', R_PROFILE='/dev/null',
               R_MAKEVARS_USER=str(makevars), R_MAKEVARS_SITE='/dev/null',
               INCLUDE_DIR=str(common), JASP_R_INTERFACE_LIBRARY='',
               GITHUB_JASP_DESKTOP_FILES='', SDKROOT=sdk, MAKE='make -j2')
    r_exe = r_home / 'bin/R'
    r_version = capture([str(r_exe), '--vanilla', '--slave', '-e', 'cat(as.character(getRversion()))'], env=env)
    if r_version != lock['r_version']:
        raise ValueError('Unexpected embedded R version')
    command = [str(r_exe), 'CMD', 'INSTALL', '--no-html', '--no-multiarch', '--with-keep.source',
               '--library=' + str(work / 'library'), str(source)]
    provenance = {
        'schema_version': 1, 'status': 'BUILDING',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'jaspbase_version': lock['jaspbase_version'], 'jaspbase_commit': lock['jaspbase_commit'],
        'common_commit': lock['common_commit'], 'common_files_sha256': common_hashes,
        'source_archives': lock['source_archives'], 'input_lock_sha256': sha256(args.lock),
        'recipe_sha256': sha256(Path(__file__)),
        'original_rcpp_tree_sha256': original_rcpp_hash,
        'original_jaspbase_tree_sha256': original_jaspbase_hash,
        'rcpp_headers_version': lock['rcpp_version'],
        'rcpp_header_count': len(file_hashes(build_rcpp / 'include')),
        'toolchain': {'compiler': capture([compiler, '--version']), 'compiler_sha256': sha256(Path(compiler)),
                      'sdk': sdk, 'sdk_version': sdk_version, 'r_version': r_version,
                      'r_executable_sha256': sha256(r_home / 'bin/exec/R'),
                      'r_makeconf_sha256': sha256(r_home / 'etc/Makeconf'),
                      'cxx_standard': 'C++20', 'architecture': 'arm64', 'deployment_target': '11.0',
                      'user_makevars': makevars.read_text()},
        'source_changes': 'Added 49 unchanged pinned Common files; no original jaspBase source files edited. configure generates src/Makevars.',
        'install_log': os.path.relpath(work / 'install.log', library.parent),
        'load_log': os.path.relpath(work / 'load-check.log', library.parent),
        'installed_common_directory': 'include/Common',
        'install_command': command,
        'configuration': {key: env[key] for key in (
            'JASP_R_HOME', 'R_HOME', 'R_LIBS', 'R_LIBS_USER', 'R_LIBS_SITE',
            'R_ENVIRON_USER', 'R_ENVIRON', 'R_PROFILE_USER', 'R_PROFILE',
            'R_MAKEVARS_USER', 'R_MAKEVARS_SITE', 'INCLUDE_DIR',
            'JASP_R_INTERFACE_LIBRARY', 'SDKROOT', 'MAKE')},
    }
    journal = work / 'build-provenance.json'
    write_json(journal, provenance)
    print('Building jaspBase from pinned package and Common sources; log:', work / 'install.log', flush=True)
    with (work / 'install.log').open('w') as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
    provenance['install_exit_code'] = result.returncode
    if result.returncode:
        provenance['status'] = 'FAILED'
        write_json(journal, provenance)
        raise RuntimeError('jaspBase source installation failed; see ' + str(work / 'install.log'))
    staged = work / 'library/jaspBase'
    binary = staged / 'libs/jaspBase.so'
    architectures = capture(['/usr/bin/lipo', '-archs', str(binary)])
    if architectures != 'arm64':
        raise ValueError('Rebuilt jaspBase is not arm64: ' + architectures)
    # Load with the unmodified final Rcpp, not the build-only header copy.
    load_env = env.copy()
    load_env['R_LIBS_USER'] = os.pathsep.join(map(str, [work / 'library', library]))
    load_env['JASPBASE_EXPECTED_PACKAGE'] = str(staged)
    expression = '''
      library(jaspBase)
      stopifnot(as.character(packageVersion("jaspBase")) == "0.20.4",
                as.character(packageVersion("Rcpp")) == "1.1.1",
                normalizePath(find.package("jaspBase")) == normalizePath(Sys.getenv("JASPBASE_EXPECTED_PACKAGE")))
      cpp <- jaspBase:::create_cpp_jaspResults("Pinned Common source check", NULL)
      cpp$setOptions("{\\"sourceBuildCheck\\":true}")
      results <- jaspBase:::jaspResultsR$new(cpp)
      stopifnot(inherits(results, "jaspResultsR"))
      cat("PASS: rebuilt jaspBase loaded and native JASP results/JSON objects instantiated.\\n")
      print(sessionInfo())
    '''
    with (work / 'load-check.log').open('w') as log:
        result = subprocess.run([str(r_exe), '--vanilla', '--slave', '-e', expression],
                                env=load_env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        provenance['status'] = 'FAILED'
        write_json(journal, provenance)
        raise RuntimeError('Rebuilt jaspBase native load check failed; see ' + str(work / 'load-check.log'))
    if tree_hash(library / 'Rcpp') != original_rcpp_hash:
        raise ValueError('The final Rcpp dependency changed during the build')
    # Check original source files after configure/compile as well. The generated
    # Makevars and compiler object files are additional outputs, not source edits.
    if any(sha256(source / name) != digest for name, digest in original_source_hashes.items()):
        raise ValueError('An original jaspBase source file changed during compilation')
    if file_hashes(common) != {**common_hashes, **{p.relative_to(common).as_posix(): sha256(p)
                                                 for p in common.rglob('*.o')}}:
        raise ValueError('Pinned Common source files changed during compilation')
    # R copies inst/include after compiling columntype.cpp. Remove its build
    # object from the installed headers; preserve all 49 original source files.
    for compiled_object in (staged / 'include/Common').rglob('*.o'):
        compiled_object.unlink()
    if file_hashes(staged / 'include/Common') != common_hashes:
        raise ValueError('Installed Common source files differ from the pinned source record')
    provenance.update(status='PASS', binary_sha256=sha256(binary),
                      binary_architecture=architectures,
                      binary_linkage=capture(['/usr/bin/otool', '-L', str(binary)]),
                      final_rcpp_tree_sha256=tree_hash(library / 'Rcpp'),
                      install_log_sha256=sha256(work / 'install.log'),
                      load_log_sha256=sha256(work / 'load-check.log'),
                      generated_makevars=(source / 'src/Makevars').read_text(),
                      finished_utc=datetime.now(timezone.utc).isoformat())
    write_json(staged / 'source-provenance.json', provenance)
    backup = work / 'original-jaspBase'
    # The stage and final library are on the same workspace filesystem by default.
    # Keep the prior restored package outside the final library for audit/recovery.
    (library / 'jaspBase').rename(backup)
    try:
        shutil.copytree(staged, library / 'jaspBase', symlinks=True)
    except Exception:
        if (library / 'jaspBase').exists():
            shutil.rmtree(library / 'jaspBase')
        backup.rename(library / 'jaspBase')
        raise
    provenance['installed_jaspbase_tree_sha256'] = tree_hash(library / 'jaspBase')
    provenance['installed_provenance_sha256'] = sha256(library / 'jaspBase/source-provenance.json')
    write_json(journal, provenance)
    write_json(library.parent / 'source-build-provenance.json', provenance)
    print('PASS: pinned jaspBase source build installed; 49 Common file hashes recorded.', flush=True)
    print('Binary SHA-256:', provenance['binary_sha256'], flush=True)


if __name__ == '__main__':
    main()
