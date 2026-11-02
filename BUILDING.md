# Building the macOS public beta

The build target is **JASP 0.99.0.0, macOS Apple Silicon (arm64), embedded
R 4.5.2**. The build restores pinned dependency binaries into a fresh private
library, rebuilds jaspBase from pinned package and Common sources, adds the
libdeflate notice, and installs this module's R source. It does not compile lcmm
or read another R installation. Windows, Intel macOS and Linux builds are not
supplied or tested.

Install the matching Apple Silicon JASP release from the
[official download page](https://jasp-stats.org/download/). Also install Python
3.9 or newer and Xcode Command Line Tools with a C++20-capable Apple compiler.
No separately installed R is required. The exercised jaspBase source-build
toolchain is **Apple clang 21.0.0 (clang-2100.1.1.101)**, compiling for arm64 with
a macOS 11 minimum target. Compiler and SDK details are captured in the build's
source provenance; another toolchain requires its own build and validation.

## One build command

From the public repository/package root (the folder containing `DESCRIPTION`,
`scripts/` and `validation/`):

```sh
sh scripts/build-macos.sh
```

The build verifies the binary-input lock, creates
`build/clean-macos-arm64/library` from empty, rebuilds jaspBase with pinned Common
and Rcpp source headers, and adds the libdeflate attribution notice to ragg.
It then installs the current module source, checks JASP's required resources,
and creates `dist/jaspTrajectories.JASPModule` and its manifest. Dependency
provenance, source-build provenance and R session information are saved beside
the library. It never modifies JASP.app or a system/user R library.

A nonempty target library is deliberately rejected. For a second build, choose a
new directory rather than mixing new and existing packages:

```sh
TRAJECTORIES_BUILD_DIR="$PWD/build/clean-macos-arm64-repeat" \
  sh scripts/build-macos.sh
```

`JASP_APP`, `TRAJECTORIES_BUILD_DIR`, `TRAJECTORIES_DIST_DIR`,
`TRAJECTORIES_CACHE_DIR` and `TRAJECTORIES_SOURCE_CACHE_DIR` may override
locations. The binary-input cache defaults to `build/downloads`; the source
cache defaults to `build/dependency-sources`. Source archives are fetched from
the pinned URLs only when absent, and must pass their recorded hashes before use.
The matching app version and package contents are still verified when locations
change. User profiles and environment files are ignored by R's `--vanilla`.
The source-build helper uses the private library and temporary build libraries
for its staged jaspBase and Rcpp headers, plus the app's embedded R library.
Module installation uses the final private library and embedded R library.
Bundling additionally uses the checksum-verified bundle-manager library shipped
in that same JASP app.

The scripts also support the original workspace layout with `jaspTrajectories/`
and `validation/` as sibling folders. Run the same commands from
`jaspTrajectories/`; generated `build/` and `dist/` then live in its parent, and
the default caches become `../build/downloads` and `../build/dependency-sources`.
`TRAJECTORIES_MODULE_DIR` and `TRAJECTORIES_PROJECT_DIR` can explicitly select the
package and workspace roots.
The examples in this document use the public package-root layout.

## Exact inputs and dependency policy

`scripts/dependencies-macos-arm64.lock.json` records the complete transitive
Depends/Imports/LinkingTo closure for the module and validation roots. It records
111 package versions and content hashes; 101 non-base packages are copied into the
private library. The other ten are base packages from the embedded R runtime.
It also fingerprints the embedded R executable and JASP bundle-manager library.
Package tree hashes include relative file paths and contents; timestamps, owners
and file modes are excluded. This lock describes the original restored inputs.
The subsequent jaspBase rebuild and attribution-file additions are recorded
separately: `dependency-provenance.json` includes the final dependency tree hashes
and the hash of `source-build-provenance.json`. The original lock is not presented
as the final transformed library's hash inventory.

| Component | Tested version | Source |
| --- | --- | --- |
| JASP | 0.99.0.0 | Official Apple Silicon app |
| R | 4.5.2 | Embedded in that app |
| lcmm | 2.2.2 | Official CRAN R 4.5 arm64 binary |
| marqLevAlg | 2.0.8 | Official CRAN R 4.5 arm64 binary |
| jaspBase | 0.20.4 | Rebuilt from commit `74daf64143f4f22d4f0e1b0a8163e6a892873fc8` and pinned Common |
| JASP Common | 0.99.0 source | Desktop commit `1204d1892b1233af145bb548fe80719f331ea693` |
| Rcpp headers | 1.1.1 | CRAN source, staged for compilation only |
| jaspGraphs | 0.20.0 | App package library |
| ggplot2 | 4.0.1 | App package library |
| nlme | 3.1-168 | App package library |
| MASS | 7.3-65 | App package library; independent validation |
| spacefillr | 0.4.0 | App package library |

The full lock contains all remaining packages. No package is selected from a
user or separately installed system R library. No unpinned CRAN version is
installed. The module's `lcmm` requirement is exactly 2.2.2 because its ordinal
prediction compatibility code depends on that version's internal model fields.
Updating lcmm requires reviewing that code and rerunning the complete validation.

The two external binary archives are downloaded only if missing from the binary cache:

- [lcmm 2.2.2 binary](https://cran.r-project.org/bin/macosx/big-sur-arm64/contrib/4.5/lcmm_2.2.2.tgz)
- [marqLevAlg 2.0.8 binary](https://cran.r-project.org/bin/macosx/big-sur-arm64/contrib/4.5/marqLevAlg_2.0.8.tgz)

Both archives must match the lock's SHA-256 digest before extraction. The cached
names are recorded in the lock. For an offline restore, prepopulate those two
files and run the dependency-restore stage:

```sh
python3 scripts/prepare-library.py \
  --library build/offline-check/library \
  --cache build/downloads --offline
```

This restores the original binary inputs only. The jaspBase source build and
notice additions described below are also required for a release build.

The build-input archive distributed with the beta preserves these two official
binaries and their lock so that a changing CRAN binary index does not silently
change the build. If an official download disappears, use the preserved cache;
do not substitute a different archive or edit its checksum merely to pass.
An app or dependency content mismatch also fails explicitly. A future supported
JASP release needs a reviewed lock update and a new full validation run.

## Pinned jaspBase source build and source cache

`scripts/rebuild-jaspbase.py` is invoked by the main build after dependency
restoration. Its lock, `scripts/jaspbase-source-build.lock.json`, selects the
jaspBase commit, Common/JSON from the matching desktop commit, and Rcpp 1.1.1
source headers. Common is staged locally and passed through `INCLUDE_DIR`, so
the upstream configure script does not fetch a mutable branch. Rcpp headers
are staged in a build-only copy; the installed Rcpp package is unchanged.

The separate `jaspTrajectories-dependency-sources-0.1.0.zip` release asset
preserves all three inputs among its 122 source/build-context archives. Extract
it, then use the resulting folder as the source cache:

```sh
TRAJECTORIES_SOURCE_CACHE_DIR="/absolute/path/jaspTrajectories-dependency-sources-0.1.0" \
  sh scripts/build-macos.sh
```

The cache must retain the archive's `cran/`, `github/` and `build-context/`
subdirectories. Prepopulating both the binary and source caches avoids dependency
downloads during the main build. The main wrapper does not have an offline flag.
For an explicitly offline jaspBase rebuild after the binary-restore stage above:

```sh
python3 scripts/rebuild-jaspbase.py \
  --library build/offline-check/library \
  --cache /absolute/path/jaspTrajectories-dependency-sources-0.1.0 \
  --jasp /Applications/JASP.app --offline
```

The helper emits `source-build-provenance.json` beside the private library and
installs `jaspBase/source-provenance.json`. Compilation work and logs are retained
under `jaspbase-source-build/` in that build directory. The normal build also
copies the full libdeflate copyright and MIT notice into `ragg/LICENSE.libdeflate`;
the module carries the same notice under `third-party/LICENSE.libdeflate`.

See [DEPENDENCY-SOURCES.md](DEPENDENCY-SOURCES.md) for source verification and
the remaining native build-provenance limits. Upstream source archives are
preserved unchanged with their notices; staged Common files and build-only Rcpp
headers are recorded as inputs to the source build.

## Test the rebuilt package

The complete test command, described in `TESTING.md`, is:

```sh
sh scripts/run-tests.sh
```

It uses the default clean build library. If the build directory was overridden,
set `TRAJECTORIES_BUILD_DIR` to the same value, or explicitly set `R_LIBS_USER` to
its `library` folder. These checks include numerical unit/integration checks,
fresh native lcmm comparisons and independent one-class likelihood/estimator
checks. Desktop controls and `.jasp` save/reopen are recorded separately in the
public validation report.

## Publishing build records without personal paths

The supplied public installer was built with both its source checkout and build
library under `/private/tmp/jaspTrajectories-public-beta-0.1.0/`. Compiler debug
information, R source references and executed build logs therefore contain a
neutral path. The build scripts use the package source and locked dependencies.

For another public release, extract the source archive into a neutral temporary
directory and set `TRAJECTORIES_BUILD_DIR` and `TRAJECTORIES_DIST_DIR` beneath
that directory. Both the source checkout and build directory matter: moving
only the final installer does not remove source paths already embedded in it.
Run the complete validation and isolated installer checks for the resulting
build before publishing it.

## What reproducibility means here

This procedure fixes dependency selection and jaspBase/Common source inputs
on the stated platform. The release validation record identifies which builds
and tests were actually executed. It does **not** promise byte-for-byte
identical `.JASPModule` files: R installation metadata, bundle timestamps and
packaging can differ. It does not establish cross-platform numerical identity or
reproducible source compilation of the upstream dependency binaries. The lock,
provenance, input-cache archive and executed validation report make those limits
inspectable.
