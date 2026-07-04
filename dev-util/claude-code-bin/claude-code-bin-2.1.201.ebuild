# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Claude Code - Anthropic's agentic coding CLI (prebuilt native binary)"
HOMEPAGE="https://code.claude.com/"

# Single self-contained native binary published per-release at
# https://downloads.claude.ai/claude-code-releases/<ver>/<platform>/claude
# (platform linux-x64 = glibc x86_64). The install.sh installer downloads
# exactly this artifact and verifies it against
# .../<ver>/manifest.json -> platforms["linux-x64"].checksum. We rename the
# bare "claude" object to a versioned distfile name.
SRC_URI="https://downloads.claude.ai/claude-code-releases/${PV}/linux-x64/claude -> ${P}"

LICENSE="Anthropic-Claude-Terms"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
QA_PREBUILT="opt/claude-code/*"

# Self-contained (Bun-compiled) executable; only needs the C library at
# runtime. Kept minimal deliberately.
RDEPEND=">=sys-libs/glibc-2.34"

S="${WORKDIR}"

# The distfile is a raw ELF executable, not an archive - skip unpack.
src_unpack() { :; }

src_install() {
	exeinto /opt/claude-code/bin
	newexe "${DISTDIR}/${P}" claude
	dosym ../../opt/claude-code/bin/claude /usr/bin/claude
}

pkg_postinst() {
	elog "Claude Code is available as 'claude' on PATH."
	elog "First run: 'claude' (it will guide you through sign-in)."
	elog "Note: upstream's install.sh normally self-manages updates under"
	elog "~/.claude; this ebuild instead pins the version via Portage, so"
	elog "update by bumping the package rather than 'claude update'."
}
