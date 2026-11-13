# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# ebuild automatically verified at 2026-11-13
EAPI=8
DESCRIPTION="Kiro command-line interface"
HOMEPAGE="https://kiro.dev/docs/cli/"
# Kiro CLI 3.x changed the upstream packaging: the tar.xz archive is gone
# and the Linux release is a zip with a single kiro-cli binary (the 2.x
# kiro-cli-chat and kiro-cli-term launchers no longer exist). The file
# name and its sha256 are published in
# https://prod.download.cli.kiro.dev/stable/index.json (one entry per
# version), which the daily bump checks against this SRC_URI.
SRC_URI="https://prod.download.cli.kiro.dev/stable/${PV}/kirocli-x86_64-linux.zip -> ${P}.zip"
S="${WORKDIR}/kirocli"
LICENSE="Kiro-CLI-EULA"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
QA_PREBUILT="opt/kiro-cli/bin/kiro-cli"
BDEPEND="app-arch/unzip"
# glibc floor: GLIBC_X86_64_MIN_MINOR=34 in the official installer
# (https://cli.kiro.dev/install); below it upstream switches to the musl
# build. The 3.x binary has no libasound DT_NEEDED (scanelf -n), so the
# media-libs/alsa-lib dependency of 2.x (kiro-cli-chat only) is gone.
RDEPEND=">=sys-libs/glibc-2.34"
src_install() {
	exeinto /opt/kiro-cli/bin
	doexe bin/kiro-cli
	dosym ../../opt/kiro-cli/bin/kiro-cli /usr/bin/kiro-cli
}
pkg_postinst() {
	local v
	for v in ${REPLACING_VERSIONS}; do
		if ver_test "${v}" -lt 3; then
			elog "Kiro CLI 3.x ships a single kiro-cli binary;"
			elog "kiro-cli-chat and kiro-cli-term no longer exist."
			break
		fi
	done
}
