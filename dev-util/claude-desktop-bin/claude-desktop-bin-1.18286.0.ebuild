# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-07-04
EAPI=8

inherit unpacker xdg

DESCRIPTION="Claude Desktop - Anthropic's Claude app: Chat, Cowork, Code (prebuilt binary)"
HOMEPAGE="https://claude.ai/download"

# Repackage of the official Debian/Ubuntu (beta) .deb from Anthropic's apt
# repository. amd64 only (upstream also ships arm64). The .deb lays files out
# under /usr (usr/lib/claude-desktop = the Electron bundle, usr/bin symlink,
# usr/share/applications + hicolor icons), which we install verbatim.
SRC_URI="https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${PV}_amd64.deb -> ${P}_amd64.deb"

LICENSE="Anthropic-Claude-Terms"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
QA_PREBUILT="usr/lib/claude-desktop/*"

# Debian Depends of the .deb mapped to Gentoo, plus the usual Electron/
# Chromium runtime set (cf. dev-util/kiro-bin). Cowork's VM features
# additionally want app-emulation/qemu + KVM group membership at runtime;
# those are optional and intentionally not hard deps (chat/code work without).
RDEPEND="
	>=sys-libs/glibc-2.34
	dev-libs/glib:2
	dev-libs/nss
	dev-libs/nspr
	app-crypt/libsecret
	x11-libs/gtk+:3
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libXtst
	x11-libs/libxkbcommon
	x11-libs/libdrm
	x11-libs/cairo
	x11-libs/pango
	app-accessibility/at-spi2-core
	media-libs/alsa-lib
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	sys-apps/util-linux
	x11-misc/xdg-utils
	sys-apps/xdg-desktop-portal
"

S="${WORKDIR}"

src_unpack() {
	# unpacker eclass handles the .deb (extracts data.tar into ${WORKDIR}).
	unpacker_src_unpack
}

src_install() {
	# Install the extracted /usr tree verbatim. cp -a preserves the
	# usr/bin/claude-desktop -> ../lib/claude-desktop/claude-desktop symlink,
	# the Electron bundle, the .desktop entry and hicolor icons.
	[[ -d usr ]] || die "unexpected .deb layout: no usr/ after unpack"
	cp -a usr "${ED}/" || die "failed to install /usr tree"

	# Electron's sandbox helper must be setuid root or the app aborts with a
	# SUID sandbox error (unless run with --no-sandbox).
	if [[ -f "${ED}/usr/lib/claude-desktop/chrome-sandbox" ]]; then
		fperms 4755 /usr/lib/claude-desktop/chrome-sandbox
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "Claude Desktop installed. Launch from your menu (entry 'Claude') or"
	elog "run 'claude-desktop'. Sign in with your Anthropic account."
	elog
	elog "Claude Code and Cowork tabs require a paid plan. Cowork additionally"
	elog "needs hardware virtualization (KVM): add yourself to the kvm group"
	elog "  ( usermod -aG kvm <user> )  and install app-emulation/qemu."
	elog
	elog "This is Anthropic's Linux BETA app, packaged for Debian/Ubuntu; on"
	elog "Gentoo it is provided as-is. It does not self-update - bump the"
	elog "package to upgrade."
}

pkg_postrm() {
	xdg_pkg_postrm
}
