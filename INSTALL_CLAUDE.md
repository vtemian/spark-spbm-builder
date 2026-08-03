# INSTALL_CLAUDE.md

Facts, decisions and traps for this repo. `README.md` says what the package is;
this says how the archive behaves and what it will reject.

Packaging lives in `debian-spbm/` and is copied over the unpacked upstream tree
by `make prepare`. Upstream is fetched as a tarball, never cloned.

## Hard rules

1. **`SPBM_COMMIT_EPOCH` moves with `SPBM_COMMIT`.** Both live in `VERSIONS`.
   Get it with `git -C <clone> show -s --format=%at <commit>`, or from
   `https://api.github.com/repos/antheas/spark_hwmon/commits/<sha>`.
2. **Never set the tarball mtime to `0`.** See "pre-1975 timestamps" below.
3. **`SPBM_VERSION` must equal `PACKAGE_VERSION` in upstream's `dkms.conf`.**
   That file hardcodes the version into its build and clean paths.
4. **Never reuse an upstream version string after changing how the tarball is
   packed.** The `.orig.tar.gz` is content-addressed by the archive.
5. **noble only.** jammy has no `dh-dkms`.
6. Do not add a series to the matrix to "test more". Each series regenerates and
   re-uploads the orig tarball, and the second one gets rejected.

## Releasing

Pushing to `main` is the release. The `ppa` job in
`.github/workflows/build.yml` is gated on
`github.ref == 'refs/heads/main' && github.event_name == 'push'`; pull requests
build and verify but never upload.

The Debian version is `$(SPBM_UPSTREAM)-$(BUILD_DIST)$(BUILD_VERSION)`, and
`BUILD_VERSION` is `~ppa$(GITHUB_RUN_NUMBER)+$(GITHUB_REF_NAME)`. The run number
always increases, so each push gets a fresh Debian revision automatically. Only
the **upstream** half needs manual care.

To move to a new upstream commit: update `SPBM_COMMIT` and `SPBM_COMMIT_EPOCH`
together, check `SPBM_VERSION` against upstream's `dkms.conf`, push.

## Launchpad rules that have actually rejected uploads here

**Pre-1975 file timestamps.** Launchpad refuses any binary containing a file
older than 1975:

```
spbm-dkms_..._all.deb: has 2 file(s) with a time stamp too far in the past
(e.g. usr/src/spbm-0.3.0/Makefile [Thu Jan  1 00:00:00 1970]).
```

`--mtime=@0` was added to make the orig tarball reproducible. `dh_install`
preserves mtimes into the `.deb`, so the epoch propagated all the way through.
**This check runs after the build succeeds.** The build page shows a green
"Successfully built" for the source and then the state `Failed to upload`;
nothing on the build log says why. The fix is the upstream commit's own date,
which is fixed (so still reproducible) and real. `.github/workflows/build.yml`
now fails the build on any pre-1975 timestamp so this cannot reach the archive
again.

**One `.orig.tar.gz` per upstream version, byte-for-byte.** The archive keeps
the first orig it accepts for a given upstream version and rejects any later
upload whose orig differs. This is why `SPBM_UPSTREAM` carries the commit, and
why changing the packing without changing the version is rule 4 above.
`0.3.0+git352c76e` is spent — it holds the epoch-stamped tarball forever.

**`3.0 (quilt)` requires an orig tarball**, and GitHub's archive cannot be used
directly: its top-level directory is named after the commit, not
`<package>-<version>`. `make prepare` repacks it before `debian/` exists.

**`debsign` insists on a tty.** `make source` therefore builds unsigned
(`dpkg-buildpackage -d -S -sa -us -uc`) and signs as a separate step via
`gpg-batch-wrapper.sh`, which supplies the passphrase from `$GPG_PASSPHRASE`
with `--pinentry-mode loopback`. Do not collapse this back into `debuild`.

**CI needs `build-essential` explicitly.** `dpkg-checkbuilddeps` does not treat
it as implied, and the runner image does not satisfy it.

## Diagnosing a package that never appears

The web UI does not show rejection reasons and Launchpad only emails them. The
API does show state:

```sh
A='https://api.launchpad.net/devel/~vladtemian/+archive/ubuntu/spark-spbm'
curl -sG "$A" --data-urlencode 'ws.op=getPublishedSources'    # accepted sources
curl -sG "$A" --data-urlencode 'ws.op=getBuildRecords'        # build outcomes
curl -sG "$A" --data-urlencode 'ws.op=getPublishedBinaries'   # what apt will see
```

`getBuildRecords` omits builds that have not run yet, so a brand-new upload
looks absent. Use the source publication's `getBuilds` instead — take
`self_link` from `getPublishedSources` and call `?ws.op=getBuilds` on it.

When a build reads `Failed to upload`, the reason is in its upload log, which is
not linked from the build page:

```
https://launchpad.net/~vladtemian/+archive/ubuntu/spark-spbm/+build/<id>/+files/upload_<id>_log.txt
```

That file is what identified the timestamp rejection. Read it before theorising.

## Architectures

The PPA has **only amd64** enabled (`.../processors` reports `['amd64']`), and
the Spark is arm64. That is not a problem here: `spbm-dkms` is
`Architecture: all`, and arch-independent binaries are published into every
architecture's index. Verify with

```sh
curl -s https://ppa.launchpadcontent.net/vladtemian/spark-spbm/ubuntu/dists/noble/main/binary-arm64/Packages.gz \
  | gunzip | grep -A5 '^Package: spbm-dkms'
```

before concluding arm64 needs enabling. Enabling arm64 would only add a
redundant second build of the same arch-all package.

## Signing

GitHub Actions secrets `PGP_KEY` (armoured private key) and `GPG_PASSPHRASE`.
The workflow imports the key, sets ownertrust to `6` and writes
`pinentry-mode loopback` into `~/.gnupg/gpg.conf` — all three are required or
signing hangs waiting for a prompt that never comes. Key
`80D44EA49E4F2C6C598A97BE2A653CE5A3C5CF7D`, which is the one registered on the
Launchpad account; an upload signed by anything else is rejected outright.

## Archive state needing manual cleanup

Only a human with Launchpad credentials can do these, at
<https://launchpad.net/~vladtemian/+archive/ubuntu/spark-spbm/+packages>:

- `0.3.0-jammy~ppa5+main` sits in `Dependency wait` and will retry forever,
  because jammy has no `dh-dkms`. Delete it.
- `0.3.0+git352c76e-noble~ppa7+main` is superseded and its build is
  `Failed to upload` (the timestamp bug). Harmless, deletable.

## Rejected, with evidence

- **jammy in the matrix** — no `dh-dkms` on 22.04, so `sbuild` reports
  `sbuild-build-depends-main-dummy : Depends: dh-dkms but it is not installable`
  and the build never completes.
- **`--mtime=@0` for reproducibility** — rejected by the archive; see above.
- **Building the module out of tree and shipping a binary `.ko`** — a `.ko` is
  bound to one kernel ABI and Secure Boot needs it signed by a trusted key.
  DKMS builds and signs on the target instead, which is why the package is
  `Architecture: all`.
