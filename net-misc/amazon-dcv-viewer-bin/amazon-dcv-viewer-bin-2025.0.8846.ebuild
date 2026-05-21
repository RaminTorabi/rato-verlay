# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-09
EAPI=8

# el9 RPMs use zstd compression - must be set before inherit rpm
RPM_COMPRESS_TYPE=zstd
inherit rpm xdg-utils

DESCRIPTION="Amazon DCV remote display client (prebuilt binary)"
HOMEPAGE="https://aws.amazon.com/hpc/dcv/"

# Versioned distfile. AWS hosts per-release RPMs at
# https://d1uj6qtbmh3dt5.cloudfront.net/<release>/Clients/nice-dcv-viewer-<PV>-1.el9.x86_64.rpm
# Rename to ${P}.rpm so each ebuild has a stable Manifest-addressable distfile.
SRC_URI="https://d1uj6qtbmh3dt5.cloudfront.net/${PV%.*}/Clients/nice-dcv-viewer-${PV}-1.el9.x86_64.rpm -> ${P}.rpm"

LICENSE="NICE-DCV-EULA"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror bindist"

# The viewer ships vendored shared libraries under its own subdir
# (usr/lib64/dcvviewer/) and a native binary under usr/libexec/dcvviewer/.
# Both must be marked as prebuilt to suppress QA strip/revdep-rebuild.
QA_PREBUILT="
	usr/lib64/dcvviewer/*
	usr/lib64/girepository-1.0/*
	usr/libexec/dcvviewer/*
	usr/libexec/${PN}/*
"

RDEPEND="
	sys-libs/glibc
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXext
	x11-libs/libXrandr
	x11-libs/libXi
	media-libs/mesa
	media-libs/fontconfig
	media-libs/freetype
	dev-libs/glib
	x11-libs/gtk+:3
	x11-libs/cairo
	x11-libs/pango
	media-libs/gst-plugins-base
	media-libs/gstreamer
	dev-libs/nss
	dev-libs/nspr
	dev-libs/libpcre2
"

S="${WORKDIR}"

src_unpack() {
	# rpm.eclass prepends DISTDIR automatically - pass only the filename.
	rpm_unpack "${P}.rpm"
}

src_install() {
	# The RPM lays everything out under usr/{bin,lib64,libexec,share}.
	# The bundled shared libs live under usr/lib64/dcvviewer/ (a private
	# subdir, no collision with system libs) and the native binary lives
	# under usr/libexec/dcvviewer/dcvviewer. The usr/bin/dcvviewer
	# wrapper references libexec and the private lib64 subdir, so the
	# cleanest install is to preserve the RPM's natural layout under /.
	#
	# We copy with cp -a (not doins/doexe) because the tree contains:
	#   - symlinks to versioned .so files
	#   - usr/lib/.build-id/** symlinks into ../../../libexec and lib64
	#   - subdirs with executable Python/shell helpers
	# doins and doexe trigger die on these edge cases in EAPI 8.

	local tree
	for tree in bin lib lib64 libexec share; do
		if [[ -d "${WORKDIR}/usr/${tree}" ]]; then
			dodir "/usr/${tree}"
			cp -a "${WORKDIR}/usr/${tree}"/. "${ED}/usr/${tree}/" \
				|| die "cp /usr/${tree} failed"
		fi
	done

	# usr/bin/dcvviewer must be executable (cp -a should preserve but be safe).
	if [[ -f "${ED}/usr/bin/dcvviewer" ]]; then
		chmod 0755 "${ED}/usr/bin/dcvviewer" || die
	fi

	# The native binary.
	if [[ -f "${ED}/usr/libexec/dcvviewer/dcvviewer" ]]; then
		chmod 0755 "${ED}/usr/libexec/dcvviewer/dcvviewer" || die
	fi
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update
	elog "Amazon DCV viewer installed. Launch with: dcvviewer <connection-url>"
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}
