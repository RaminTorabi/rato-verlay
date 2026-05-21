# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-07
EAPI=8

PYTHON_COMPAT=( python3_{10..13} )

# The AL2023 RPM uses Zstd payload compression. Declared before
# `inherit rpm` so rpm.eclass's _rpm_set_globals sees it and wires up
# the correct BDEPEND: either `>=app-arch/rpm-4.19.0[zstd]` (preferred,
# uses rpm2archive + libarchive) or `app-arch/rpm2targz` as the
# fallback unpacker. Without this, rpm.eclass falls back to rpm2targz
# which works but emits a QA warning each build.
#
# See https://devmanual.gentoo.org/eclass-reference/rpm.eclass/ for
# the complete list of supported compression types.
RPM_COMPRESS_TYPE=zstd

inherit python-single-r1 rpm systemd

DESCRIPTION="Amazon EFS and S3 Files mount helpers (prebuilt binary)"
HOMEPAGE="https://github.com/aws/efs-utils"

# AWS publishes pre-built RPMs for their supported distros at
# amazon-efs-utils.aws.com. We pull the AL2023 x86_64 RPM because:
#   - AL2023 ships glibc 2.34 (matches our Gentoo baseline, 2.41)
#   - The efs-proxy binary in the RPM is compiled against AL2023's
#     GCC 11, avoiding the AWS-LC FIPS module assembler error that
#     blocks source builds on GCC >= 14 (Gentoo's current default).
#   - AWS's official binary — the same one millions of EC2 instances
#     use — matches exactly what AWS tests in production.
#
# URL format is fixed once the version is known; see
# https://amazon-efs-utils.aws.com/efs-utils-installer.sh for the
# repo layout.
SRC_URI="https://amazon-efs-utils.aws.com/repo/rpm/amazon/2023/x86_64/amazon-efs-utils-${PV}-1.amzn2023.x86_64.rpm -> ${P}.rpm"

LICENSE="MIT"
SLOT="0"
# Conservative: mark unstable until we validate a successful boot +
# mount on a real Update AMI. Flip to "amd64" once proven.
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
# Paths are relative to ${D}, no leading slash. efs-proxy is the only
# prebuilt binary that isn't a Python script. `strip` is restricted
# globally above because the binary has embedded BuildID and stripping
# risks breaking the FIPS cryptographic validation.
QA_PREBUILT="sbin/efs-proxy"

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

# Runtime deps mirror the upstream amazon-efs-utils.spec / .control.
# efs-proxy is dynamically linked against glibc + the kernel's NFS
# client stack; Python helpers need botocore when CloudWatch logging
# is enabled (optional, not listed here to avoid pulling the world in).
RDEPEND="
	${PYTHON_DEPS}
	net-fs/nfs-utils
	>=net-misc/stunnel-4.56
	>=dev-libs/openssl-1.0.2
	sys-apps/util-linux
	sys-apps/which
	sys-libs/glibc
"

# python-single-r1 needs Python at build time too (pkg_setup runs
# python_setup, src_prepare runs python_fix_shebang). Append to
# rpm.eclass's BDEPEND (set dynamically by _rpm_set_globals based on
# RPM_COMPRESS_TYPE=zstd above) rather than overwriting it — that
# would drop the rpm2archive/rpm2targz dep and break src_unpack.
BDEPEND+=" ${PYTHON_DEPS}"

# rpm_unpack drops the RPM payload into ${WORKDIR}, not into ${S}.
S="${WORKDIR}"

# Mutually exclusive with net-fs/amazon-efs-utils — both install the
# same files (mount.efs, mount.s3files, efs-proxy, watchdog, systemd
# unit, configs). RDEPEND-level blocker avoids the Portage file
# collision check.
RDEPEND+=" !net-fs/amazon-efs-utils"

src_unpack() {
	# rpm.eclass prepends DISTDIR automatically - pass only the filename.
	rpm_unpack "${P}.rpm"
}

src_prepare() {
	default

	# AL2023 bakes /usr/bin/python3 (Python 3.9) into the RPM's shebang
	# lines. python_fix_shebang rewrites them to the selected Python
	# slot on this host (matches PYTHON_COMPAT + python-single-r1).
	# The Python helpers sit under /usr/sbin/ in the RPM — they will be
	# relocated to /sbin/ in src_install below.
	python_fix_shebang usr/sbin/mount.efs
	python_fix_shebang usr/sbin/mount.s3files
	python_fix_shebang usr/bin/amazon-efs-mount-watchdog
}

src_install() {
	# The RPM lays things out under usr/sbin/ and usr/bin/. We install
	# to Gentoo's conventional /sbin/ (where mount(8) looks for
	# mount.TYPE helpers) for the mount helpers, and keep the watchdog
	# under /usr/bin/.

	# Main mount helpers — go under /sbin/ so `mount -t efs` and
	# `mount -t s3files` find them.
	exeinto /sbin
	doexe usr/sbin/mount.efs
	doexe usr/sbin/mount.s3files

	# efs-proxy — the AWS-LC-FIPS Rust binary. Relocated to /sbin/
	# alongside the mount helpers (matches the upstream spec's
	# efs_bindir = /sbin on non-Amazon-Linux-3+ distros).
	doexe usr/sbin/efs-proxy

	# Watchdog daemon — lives in /usr/bin/.
	exeinto /usr/bin
	doexe usr/bin/amazon-efs-mount-watchdog

	# Python helper modules — Gentoo convention is to drop them in
	# /sbin/ next to the mount helpers, matching where the RPM puts
	# them on AL2023 (sys.path[0] resolution from /sbin/mount.efs).
	insinto /sbin
	doins -r usr/sbin/efs_utils_common
	doins -r usr/sbin/mount_efs
	doins -r usr/sbin/mount_s3files

	# Configuration files under /etc/amazon/efs/.
	insinto /etc/amazon/efs
	doins etc/amazon/efs/efs-utils.conf
	doins etc/amazon/efs/s3files-utils.conf
	insopts -m 0444
	doins etc/amazon/efs/efs-utils.crt

	# Log directory.
	keepdir /var/log/amazon/efs

	# Systemd unit for the mount watchdog.
	systemd_dounit usr/lib/systemd/system/amazon-efs-mount-watchdog.service

	# Man pages — the RPM ships them already gzipped.
	insinto /usr/share/man/man8
	doins usr/share/man/man8/mount.efs.8.gz
	doins usr/share/man/man8/mount.s3files.8.gz
}

pkg_postinst() {
	elog "amazon-efs-utils (prebuilt binary) ${PV} installed."
	elog "Built by AWS for AL2023 x86_64; runs on Gentoo with glibc >= 2.34."
	elog ""
	elog "To mount an S3 Files file system:"
	elog "  mount -t s3files <fs-id>:/ /mount/point"
	elog ""
	elog "To mount an EFS file system with TLS:"
	elog "  mount -t efs -o tls <fs-id>:/ /mount/point"
	elog ""
	elog "Enable the mount watchdog to keep TLS tunnels healthy:"
	elog "  systemctl enable --now amazon-efs-mount-watchdog.service"
}
