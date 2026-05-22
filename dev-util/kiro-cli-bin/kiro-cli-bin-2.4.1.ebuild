# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-22
EAPI=8

DESCRIPTION="Kiro command-line tools (kiro-cli, kiro-cli-chat, kiro-cli-term)"
HOMEPAGE="https://kiro.dev/docs/cli/"
SRC_URI="https://prod.download.cli.kiro.dev/stable/${PV}/kirocli-x86_64-linux.tar.xz -> ${P}.tar.xz"
S="${WORKDIR}/kirocli"

LICENSE="Kiro-CLI-EULA"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
QA_PREBUILT="opt/kiro-cli/*"

RDEPEND=">=sys-libs/glibc-2.34"

src_install() {
	# Unpack entire tree under /opt/kiro-cli/
	insinto /opt/kiro-cli
	doins -r .

	# Make the three binaries executable
	fperms 0755 /opt/kiro-cli/bin/kiro-cli
	fperms 0755 /opt/kiro-cli/bin/kiro-cli-chat
	fperms 0755 /opt/kiro-cli/bin/kiro-cli-term

	# Symlink launchers into /usr/bin
	dosym ../../opt/kiro-cli/bin/kiro-cli      /usr/bin/kiro-cli
	dosym ../../opt/kiro-cli/bin/kiro-cli-chat /usr/bin/kiro-cli-chat
	dosym ../../opt/kiro-cli/bin/kiro-cli-term /usr/bin/kiro-cli-term
}
