# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-09
EAPI=8

inherit rpm

DESCRIPTION="Amazon DCV remote display server (prebuilt binary)"
HOMEPAGE="https://aws.amazon.com/hpc/dcv/"

# 2021.3 predates el8/el9 tarballs — use el7. Binary still runs on modern
# Gentoo because DCV bundles its own libs in /opt/amazon-dcv.
MY_PV_DASH="${PV%.*}-${PV##*.}"
SRC_URI="https://d1uj6qtbmh3dt5.cloudfront.net/${PV%.*}/Servers/nice-dcv-${MY_PV_DASH}-el7-x86_64.tgz -> ${P}.tgz"

LICENSE="NICE-DCV-EULA"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
QA_PREBUILT="opt/amazon-dcv/*"

RDEPEND="
	sys-libs/glibc
	x11-libs/libX11
	x11-libs/libXext
	media-libs/mesa
"

S="${WORKDIR}"

src_unpack() {
	default
	local server_rpm
	server_rpm=$(find "${WORKDIR}" -name 'nice-dcv-server-*.x86_64.rpm' -print -quit)
	if [[ -z "${server_rpm}" ]]; then
		die "Could not find nice-dcv-server RPM in tarball"
	fi
	rpm_unpack "${server_rpm}"
}

src_install() {
	insinto /opt/amazon-dcv
	if [[ -d usr/lib64/dcv ]]; then
		doins -r usr/lib64/dcv/*
	fi
	if [[ -d etc/dcv ]]; then
		insinto /opt/amazon-dcv/etc
		doins -r etc/dcv/*
	fi
	if [[ -d usr/bin ]]; then
		local bin_file
		for bin_file in usr/bin/dcv*; do
			[[ -f "${bin_file}" ]] || continue
			exeinto /opt/amazon-dcv/bin
			doexe "${bin_file}"
			local bn
			bn=$(basename "${bin_file}")
			dosym ../../opt/amazon-dcv/bin/"${bn}" /usr/bin/"${bn}"
		done
	fi

	if [[ ! -f "${ED}/opt/amazon-dcv/bin/dcv" ]]; then
		local dcv_bin
		dcv_bin=$(find "${WORKDIR}" -name 'dcv' -type f -print -quit)
		if [[ -n "${dcv_bin}" ]]; then
			exeinto /opt/amazon-dcv/bin
			doexe "${dcv_bin}"
			dosym ../../opt/amazon-dcv/bin/dcv /usr/bin/dcv
		fi
	fi
}
