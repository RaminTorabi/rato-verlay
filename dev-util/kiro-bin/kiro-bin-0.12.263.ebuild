# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-29
EAPI=8

inherit desktop xdg

DESCRIPTION="Kiro desktop IDE — agentic AI development environment (prebuilt binary)"
HOMEPAGE="https://kiro.dev/"
SRC_URI="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/signed/${PV}/tar/kiro-ide-${PV}-stable-linux-x64.tar.gz"
S="${WORKDIR}/Kiro"

LICENSE="Kiro-EULA"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"
QA_PREBUILT="opt/kiro/*"

RDEPEND="
	>=sys-libs/glibc-2.34
	dev-libs/glib:2
	dev-libs/nss
	dev-libs/nspr
	app-crypt/libsecret
	app-crypt/gcr:0[gtk]
	x11-libs/gtk+:3
	x11-libs/libxkbcommon
	x11-libs/libdrm
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libxkbfile
	x11-libs/libxshmfence
	x11-libs/cairo
	x11-libs/pango
	media-libs/alsa-lib
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	sys-apps/util-linux
"

src_install() {
	# Install the entire upstream tree under /opt/kiro/ while preserving
	# the executable bits on the binaries. `doins` strips the +x bit, so
	# we use cp -a inside the image and then fix ownership and special
	# directory modes afterwards. This mirrors the stowe-verlay and
	# upstream-installer conventions for this prebuilt bundle.
	local dest="${ED}/opt/kiro"
	mkdir -p "${dest}" || die "mkdir failed"
	cp -a . "${dest}/" || die "cp failed"

	# Electron sandbox helper must be setuid-root; chrome-sandbox is the
	# standard binary name under resources/app. Guard in case upstream
	# renames it.
	if [[ -f "${dest}/chrome-sandbox" ]]; then
		fperms 4755 /opt/kiro/chrome-sandbox
	fi

	# Symlink the launcher into /usr/bin
	dosym ../../opt/kiro/bin/kiro /usr/bin/kiro

	# Install XDG desktop entry
	domenu "${FILESDIR}"/kiro.desktop

	# Install icon from the unpacked upstream tarball (not from FILESDIR,
	# because we do not redistribute the upstream icon artwork in the git
	# repository). The icon ships inside the tarball at the path below.
	local icon_src="${S}/resources/app/resources/linux/code.png"
	if [[ -f "${icon_src}" ]]; then
		newicon -s 256 "${icon_src}" kiro.png
	else
		ewarn "Icon not found at ${icon_src}; desktop entry will fall back to a generic icon."
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "Kiro is now available as 'kiro' on PATH."
	elog "Launch it from your desktop environment (XDG entry installed) or via the command line."
}

pkg_postrm() {
	xdg_pkg_postrm
}
