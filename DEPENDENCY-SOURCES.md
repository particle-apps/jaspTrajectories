# Dependency sources for public beta 0.1.0

The release asset `jaspTrajectories-dependency-sources-0.1.0.zip` contains source
materials for every one of the **101 R dependencies** included in the installer:
99 CRAN source packages and the two exact recorded GitHub commits for `jaspBase`
and `jaspGraphs`. It also contains **19 native-library source archives**, the
matching JASP desktop release source with Common code, and a pinned CRAN macOS
build-recipe snapshot. These are source materials, not an installer.

Keep this ZIP in GitHub **Releases**, alongside the installer and binary-input
ZIP. Its size exceeds GitHub's ordinary 100 MiB Git file limit. Do not commit the
source archives into the package repository.

## Inventory and verification

The ZIP extracts to `jaspTrajectories-dependency-sources-0.1.0/` and contains:

- `cran/`: 99 unchanged CRAN source archives, including lcmm 2.2.2 and
  marqLevAlg 2.0.8.
- `github/`: jaspBase 0.20.4 at `74daf64143f4f22d4f0e1b0a8163e6a892873fc8`
  and jaspGraphs 0.20.0 at `288d2751131ee6ac17362bd89d2ed7d9c0c67c7c`.
- `native/`: observed versions of cairo, fontconfig, FreeType, pixman, libpng,
  HarfBuzz, TIFF, WebP, Zstandard, XZ, libjpeg, FriBidi, OpenSSL, curl, libxml2,
  ICU and Expat. Separate FreeType and libpng versions are retained where binaries
  contain different versions.
- `build-context/`: JASP 0.99.0 source and a CRAN macOS recipes snapshot.
- `SOURCE-MANIFEST.json`, `SOURCE-INDEX.csv` and `SHA256SUMS.txt`: download URLs,
  versions/commits, archive hashes, licences or notice locations, and verification
  limits. The JSON is also supplied as `scripts/dependency-sources.lock.json`.
- `provenance/`: installed package metadata, binary/version evidence and the
  dependency and installer manifests. The source index identifies the installer
  SHA-256 to which this collection refers.
- `licenses/`: standard R-distributed licence texts. Package-specific copyrights,
  licences, exceptions, fonts and third-party notices remain in their original
  source archives; the module's licence does not replace them. The libdeflate
  notice is also included with the installed module and ragg dependency.

All 99 CRAN archives were checked against the installed package names, versions
and `Packaged` timestamps. All 18,940 checksums in their internal MD5 manifests
passed. The two GitHub archives were checked against all 495 Git file hashes at
the recorded commits; neither package has submodules. The additional native
sources match observed version evidence. No upstream source archive was edited.

To verify the 122 archives offline, run from the package repository:

```sh
python3 scripts/fetch-dependency-sources.py \
  --directory /absolute/path/jaspTrajectories-dependency-sources-0.1.0 \
  --verify-only
```

To restore the same archives from their recorded URLs into an empty directory,
omit `--verify-only`. The script verifies SHA-256 and R package metadata before
accepting downloads. It does not extract, install or execute the sources. The
preserved ZIP is preferable if an upstream URL later disappears.

## Pinned jaspBase source build

The installer build replaces the app-supplied jaspBase binary with a source build
using three preserved inputs:

- jaspBase 0.20.4, commit `74daf64143f4f22d4f0e1b0a8163e6a892873fc8`.
- Common/JSON from JASP desktop 0.99.0, commit
  `1204d1892b1233af145bb548fe80719f331ea693`.
- Rcpp 1.1.1 source headers, supplied in the existing CRAN archive.

`scripts/rebuild-jaspbase.py` verifies these archives against
`scripts/jaspbase-source-build.lock.json`, stages Common locally, and supplies
`INCLUDE_DIR` to the upstream configure script. This avoids its default download
from the mutable `development` branch. Rcpp's source headers are staged in a
build-only copy because the app's installed Rcpp omits some compilation headers;
the Rcpp package included in the installer is unchanged.

The build records the selected sources, compiler and resulting package in
`source-build-provenance.json` beside the private library, and installs
`jaspBase/source-provenance.json` with the rebuilt dependency. The original
binary-input lock remains a record of the restored inputs. The updated
`dependency-provenance.json` records `final_dependency_tree_sha256` and
`source_build_provenance_sha256` after the source build and notice additions.
See [BUILDING.md](BUILDING.md) for the complete build and [VALIDATION.md](VALIDATION.md)
for the checks actually completed for the resulting installer. The public release was rebuilt in a neutral temporary directory. Its provenance,
compiler metadata and R source references use that neutral location instead of a
personal home directory. Recorded paths describe the executed build; use your
own selected build directory when reproducing it.

## libdeflate attribution

The ragg binary contains statically linked libdeflate code. Its full upstream
copyright and MIT permission notice is included at
`inst/third-party/LICENSE.libdeflate` in this module's source, installed as
`third-party/LICENSE.libdeflate`, and also at `ragg/LICENSE.libdeflate` in the
bundled dependency. The accompanying README identifies the component.

The notice is preserved byte-for-byte from upstream COPYING at commit
`439f30117684c7859e0b1d4d8c57306b9ad71fd4`. It retains both **Copyright 2016 Eric
Biggers** and **Copyright 2024 Google LLC**. Selecting this notice does not assert
the unidentified libdeflate version in ragg. The notice addition does not change
ragg's compiled code.

## Reproduce the source build

The normal `sh scripts/build-macos.sh` command invokes the pinned jaspBase build.
To reuse the preserved sources, extract the dependency-source ZIP and select its
root as the source cache:

```sh
TRAJECTORIES_SOURCE_CACHE_DIR="/absolute/path/jaspTrajectories-dependency-sources-0.1.0" \
  sh scripts/build-macos.sh
```

Keep the extracted `cran/`, `github/` and `build-context/` layout intact. All three
source inputs are already among the 122 supplied archives. The helper can also
be run offline against an existing private library prepared with the binary lock:

```sh
python3 scripts/rebuild-jaspbase.py \
  --library build/offline-check/library \
  --cache /absolute/path/jaspTrajectories-dependency-sources-0.1.0 \
  --jasp /Applications/JASP.app --offline
```

This compiles jaspBase; it does not by itself assemble an installer or run the
validation suite. It requires the matching JASP app and an Apple C++20 compiler;
see [BUILDING.md](BUILDING.md).

## Remaining provenance limits

The rebuilt jaspBase has explicit Common inputs. No claim is made that it is
byte-identical to the earlier app-supplied binary or that the earlier binary used
this same Common revision.

Sources for the identified embedded native-library versions are included, but
exact historical patches, recipes and compiler settings are not established for
all retained binaries. The CRAN macOS recipes snapshot is reference material,
not a verified description of every native build, and the native audit is not
proof that every statically linked component has been identified. In particular,
ragg's precise libdeflate version and matching source remain unidentified; no
guessed version is supplied. Its required copyright and permission notice is
provided as described above. Apple system dylibs are linked from the operating
system and are not redistributed by this installer.

These limits do not imply that a byte-identical rebuild is required or establish
a licence violation. The collection is not a comprehensive legal certification.
The JASP desktop archive supplies the selected Common files and build context;
its desktop submodules are not expanded, so it is not a standalone desktop build
distribution.

The retained `data.table` DESCRIPTION says `x86_64`/RSPM, while the actual bundled
shared library is arm64 and its compiler record identifies an osxcross arm64
build. Its source version and `Packaged` timestamp match the collected CRAN
archive. Original metadata is preserved rather than silently corrected.
