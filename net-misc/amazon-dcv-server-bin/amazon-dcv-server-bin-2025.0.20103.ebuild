# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-09
EAPI=8

inherit rpm

DESCRIPTION="Amazon DCV remote display server (prebuilt binary)"
HOMEPAGE="https://aws.amazon.com/hpc/dcv/"

# Versioned distfile. AWS hosts per-release tarballs at
# https://d1uj6qtbmh3dt5.cloudfront.net/<release>/Servers/nice-dcv-<PV_DASH>-<elN>-x86_64.tgz
# where <PV_DASH> is the PV with the final dot replaced by a dash, and <elN>
# depends on the release era. We rename to ${P}.tgz so each ebuild has a
# unique, stable distfile name.
MY_PV_DASH="${PV%.*}-${PV##*.}"
SRC_URI="https://d1uj6qtbmh3dt5.cloudfront.net/${PV%.*}/Servers/nice-dcv-${MY_PV_DASH}-el9-x86_64.tgz -> ${P}.tgz"

LICENSE="NICE-DCV-EULA"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
QA_PREBUILT="usr/libexec/dcv/* usr/lib64/dcv/* usr/bin/dcv*"

RDEPEND="
	sys-libs/glibc
	x11-libs/libX11
	x11-libs/libXext
	media-libs/mesa
"

S="${WORKDIR}"

src_unpack() {
	default
	# The tarball contains RPMs; extract the server RPM
	local server_rpm
	server_rpm=$(find "${WORKDIR}" -name 'nice-dcv-server-*.x86_64.rpm' -print -quit)
	if [[ -z "${server_rpm}" ]]; then
		die "Could not find nice-dcv-server RPM in tarball"
	fi
	rpm_unpack "${server_rpm}"
}

src_install() {
	# The nice-dcv-server RPM already lays every file out under the FHS
	# prefixes that DCV's own wrapper scripts (/usr/bin/dcv*) hardcode:
	#
	#   /usr/libexec/dcv/        backend ELF binaries (dcvserver, dcvagent,
	#                            Xdcv, dcvsessionlauncher, ...)
	#   /usr/lib64/dcv/          private shared libraries + modules
	#   /usr/bin/dcv*            wrapper scripts (reference the two paths
	#                            above via programsdir=/usr/libexec/dcv and
	#                            pkglibdir=/usr/lib64/dcv)
	#   /etc/dcv/                dcv.conf + default config
	#   /etc/pam.d/dcv           PAM stack for the default "system" auth
	#   /usr/lib/systemd/system/dcvserver.service
	#
	# The previous revision relocated only the libs, config, and wrappers
	# under /opt/amazon-dcv and dropped /usr/libexec/dcv entirely, so the
	# wrappers failed with "/usr/libexec/dcv/dcvserver: No such file or
	# directory" and no systemd unit was ever installed. Install the
	# extracted tree verbatim so the wrappers resolve and dcvserver.service
	# is present + enableable.
	local d
	for d in usr etc opt lib; do
		[[ -d ${d} ]] || continue
		cp -a "${d}" "${ED}/" || die "failed to install /${d} tree"
	done

	[[ -f "${ED}/usr/libexec/dcv/dcvserver" ]] \
		|| die "dcvserver backend binary missing after install - RPM layout changed"
}
