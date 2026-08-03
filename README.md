# spark-spbm-builder

Debian package builder for [`antheas/spark_hwmon`](https://github.com/antheas/spark_hwmon),
the hwmon driver that exposes whole-system power telemetry on an NVIDIA DGX
Spark.

Produces `spbm-dkms`, a DKMS source package. The target machine compiles the
module against its own running kernel, so one `Architecture: all` package serves
every Spark and survives kernel upgrades.

## Why

`nvidia-smi` reports the GPU rail alone, which does not span even its own
package: NVIDIA rates the GB10 SoC at 140 W for CPU and GPU together inside a
240 W system. The firmware measures the rest and keeps it in the System Power
Budget Manager region, which no shipped driver binds. This packages the driver
that does, so people can `apt install` it instead of building by hand and
signing modules themselves.

## Build

```sh
make deb          # binary package, needs a Debian/Ubuntu host
make source       # signed source package for dput
make clean
```

`VERSIONS` pins upstream by **commit**, not branch. Upstream publishes no tags,
and a moving branch would silently change what a rebuild produces, which is not
acceptable for something that installs a kernel module.

`SPBM_VERSION` must match `PACKAGE_VERSION` in upstream's `dkms.conf`. That file
hardcodes the version into its build and clean paths, so a mismatch makes DKMS
build in a directory nothing installed to.

## Two things that will waste your afternoon

**`dh --with dkms` needs `dh-dkms`, not `dkms`.** On noble the debhelper
sequence moved into its own package. Without it the build fails with
`unable to load addon dkms`.

**`dh_dkms` silently does nothing without `debian/<package>.dkms`.** It needs
either the config itself or a file naming upstream's. Miss it and the package
builds cleanly, installs cleanly, ships the source to `/usr/src/spbm-0.3.0/`,
and registers nothing with DKMS. `dkms status` is simply empty. The CI job
checks for the maintainer scripts specifically because this failure looks like
success.

## Publishing

Pushes to `main` build the package and upload it to
[`ppa:vladtemian/spark-spbm`](https://launchpad.net/~vladtemian/+archive/ubuntu/spark-spbm)
for noble and jammy.

Upstream declares `MODULE_LICENSE("GPL")` in `spbm.c` but ships no `LICENSE`
file. A pull request adding the matching GPL-2.0 text is open at
[antheas/spark_hwmon#1](https://github.com/antheas/spark_hwmon/pull/1);
`debian-spbm/copyright` states the position until it lands.

## Installing

Once published, [sparkup](https://github.com/vtemian/sparkup)'s `spbm` role adds
the PPA, installs the package, and queues the module signing key for enrolment.

Secure Boot rejects modules signed by a key it does not trust, and a PPA cannot
get modules signed by Canonical's key, so DKMS signs with a key generated on the
target machine. That key enters the trust store only through **MokManager**, a
screen shim shows before the OS starts. It needs a keyboard, once per machine,
and no amount of packaging removes it.
