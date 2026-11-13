# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-11-13
EAPI=8

inherit desktop xdg

DESCRIPTION="Kiro Crew - persistent, self-learning AI agent workspace (prebuilt AppImage)"
HOMEPAGE="https://kiro.dev/docs/crew/ https://github.com/kirodotdev/KiroCrew"

# Repackage of the official Linux AppImage from the (Apache-2.0,
# open-sourced 2026-08-04) kirodotdev/KiroCrew GitHub releases. The
# AppImage bundles the Electron desktop app plus the Python Gateway
# backend (resources/backend-dist, PyInstaller-style), so no host
# Python is needed. amd64 only upstream.
# Since 0.4.1 upstream names the x86_64 AppImage KiroCrew-<ver>-x86_64.AppImage
# (KiroCrew-<ver>.AppImage no longer exists).
SRC_URI="https://github.com/kirodotdev/KiroCrew/releases/download/v${PV}/KiroCrew-${PV}-x86_64.AppImage -> ${P}.AppImage"
S="${WORKDIR}/squashfs-root"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
# strip: prebuilt Electron + PyInstaller binaries; mirror: fetch from
# the upstream release endpoint only (no local distfile mirroring).
RESTRICT="strip mirror"
QA_PREBUILT="opt/kirocrew/*"

# Standard Electron/Chromium runtime set (cf. dev-util/kiro-bin and
# dev-util/claude-desktop-bin). The bundled Python backend is fully
# self-contained. Talking to the LLM additionally wants
# dev-util/kiro-cli-bin at runtime (Agent Client Protocol provider),
# but the dashboard can install/guide that itself, so it is expressed
# as an elog hint rather than a hard dep.
RDEPEND="
	>=sys-libs/glibc-2.34
	dev-libs/glib:2
	dev-libs/nss
	dev-libs/nspr
	app-crypt/libsecret
	x11-libs/gtk+:3
	x11-libs/libnotify
	x11-libs/libxkbcommon
	x11-libs/libdrm
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libXtst
	x11-libs/cairo
	x11-libs/pango
	app-accessibility/at-spi2-core
	media-libs/alsa-lib
	media-libs/mesa
	net-print/cups
	dev-libs/expat
	sys-apps/dbus
	sys-apps/util-linux
	virtual/libudev
	virtual/libcrypt:=
"
# net-print/cups, dev-libs/expat, virtual/libudev: DT_NEEDED of the 0.12
# Electron binary (libcups.so.2, libexpat.so.1, libudev.so.1; scanelf -n).
# Without cups it does not start at all.
# virtual/libcrypt: the bundled PyInstaller Python 3.12 links
# libcrypt.so.1 (lib-dynload/_crypt); on glibc>=2.39 that is a
# separate provider package, so declare it (QA notice otherwise).

src_unpack() {
	# An AppImage is an ELF runtime with an appended squashfs. Extract
	# it via the runtime's own --appimage-extract (no FUSE needed at
	# build time, and no fragile squashfs-offset computation). The
	# artifact's SHA256 was verified against the GitHub release digest
	# when the Manifest was generated, and portage re-verifies the
	# Manifest hashes before we ever execute it here.
	cp "${DISTDIR}/${P}.AppImage" "${WORKDIR}/" || die "cp failed"
	chmod +x "${WORKDIR}/${P}.AppImage" || die "chmod failed"
	cd "${WORKDIR}" || die
	"./${P}.AppImage" --appimage-extract >/dev/null || die "AppImage extract failed"
}

src_install() {
	# Install the extracted AppDir under /opt/kirocrew/ preserving
	# executable bits (doins strips +x; same convention as kiro-bin).
	local dest="${ED}/opt/kirocrew"
	mkdir -p "${dest}" || die "mkdir failed"
	cp -a . "${dest}/" || die "cp failed"
	# cp -a keeps the AppDir's modes, and upstream ships the AppDir root
	# and locales/, resources/, usr/ as 0700, which locks non-root users
	# out (EACCES from Electron on resources/app.asar). Normalise the
	# whole tree: directories 0755, files 0644, executables 0755 (X keeps
	# the execute bit only where upstream set one). chrome-sandbox gets
	# its setuid bit below. Reported in
	# https://github.com/RaminTorabi/rato-verlay/pull/1 (Marius Peter).
	chmod -R u=rwX,go=rX "${dest}" || die "chmod failed"

	# The AppImage-internal desktop file (Exec=AppRun --no-sandbox) and
	# .DirIcon are AppImage plumbing; replace with proper XDG entries.
	rm -f "${dest}"/*.desktop "${dest}/.DirIcon"

	# Prune bundled binaries that can never load on this host
	# (~amd64 = linux/x64/glibc), same policy as dev-util/kiro-bin:
	#  - the vendored llama.cpp libs for every non-host platform
	#    (linux_aarch64, macos_*, win_amd64; Portage's soname scanner
	#    flags the aarch64 ones' unresolved ld-linux-aarch64 deps),
	#  - AppImage legacy-desktop compat shims (libappindicator/
	#    libgconf) that dangle against libs Gentoo no longer ships;
	#    Electron only dlopens them opportunistically on ancient
	#    desktops and runs fine without.
	# Guarded find so a future upstream layout change can never die.
	local _vend
	while IFS= read -r -d '' _vend; do
		rm -rf "${_vend}"
	done < <(find "${dest}"/resources/backend-dist -type d \
		-path '*/_vendor/llama_cpp_libs/*' ! -name 'linux_x86_64' \
		-print0 2>/dev/null)
	rm -f "${dest}"/usr/lib/libappindicator.so.1 "${dest}"/usr/lib/libgconf-2.so.4
	rmdir --ignore-fail-on-non-empty "${dest}/usr/lib" "${dest}/usr" 2>/dev/null || true

	# Known-benign remaining QA notice: the bundled PyInstaller
	# lib/libpython3.so carries an $ORIGIN-relative DT_NEEDED on
	# libpython3.12.so.1.0 which Portage's scanner does not resolve;
	# the target ships right next to it in the same lib/ dir.

	# Electron sandbox helper must be setuid-root so the app runs with
	# the Chromium sandbox instead of upstream's --no-sandbox fallback.
	if [[ -f "${dest}/chrome-sandbox" ]]; then
		fperms 4755 /opt/kirocrew/chrome-sandbox
	fi

	# Launcher: AppRun sets up the AppDir environment and execs the
	# bundled Electron binary. /usr/bin/kirocrew-desktop, NOT
	# /usr/bin/kirocrew - the latter is the CLI entry point of the pip
	# distribution and must stay free for a future source package.
	dosym ../../opt/kirocrew/AppRun /usr/bin/kirocrew-desktop

	# XDG desktop entry + icons from the upstream AppDir. Since 0.12 the
	# AppDir ships usr/share/icons/hicolor/<N>x<N>/apps/kirocrew-desktop.png
	# (0.2.0 had a single 1024x1024 kirocrew-electron-mac.png symlink).
	# Install the real files, never the AppDir-root symlinks (they would
	# dangle outside the AppDir).
	make_desktop_entry /opt/kirocrew/AppRun "Kiro Crew" kirocrew \
		"Development;" "StartupWMClass=kirocrew-desktop"
	local icon icon_dir icon_count=0 icon_real
	for icon in "${S}"/usr/share/icons/hicolor/*x*/apps/kirocrew-desktop.png; do
		[[ -f "${icon}" ]] || continue
		icon_dir="${icon%/apps/*}"
		icon_dir="${icon_dir##*/}"
		newicon -s "${icon_dir%x*}" "${icon}" kirocrew.png
		icon_count=$((icon_count + 1))
	done
	if (( icon_count == 0 )); then
		icon_real="$(readlink -f "${S}/kirocrew-electron-mac.png" 2>/dev/null || true)"
		if [[ -f "${icon_real}" ]]; then
			newicon -s 1024 "${icon_real}" kirocrew.png
		else
			ewarn "Upstream icon not found; desktop entry falls back to a generic icon."
		fi
	fi
}

pkg_preinst() {
	xdg_pkg_preinst
	# Portage keeps the mode of a directory that already exists on the
	# live system, so after an upgrade from 0.2.0 (installed with the
	# AppDir's 0700 directories) /opt/kirocrew would stay unreadable for
	# non-root users although the image is 0755. Fix the existing
	# directories before the merge; files are replaced with image modes.
	if [[ -d ${EROOT}/opt/kirocrew ]]; then
		find "${EROOT}/opt/kirocrew" -type d -exec chmod 0755 {} + \
			|| die "chmod of the existing /opt/kirocrew failed"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "Kiro Crew is available as 'kirocrew-desktop' (and an XDG menu entry)."
	elog "The app drives its LLM through kiro-cli (Agent Client Protocol);"
	elog "install dev-util/kiro-cli-bin or let the first launch set it up."
	elog "Persistent state lives under ~/.kiro/crew/ (KIROCREW_HOME to move it)."
	elog ""
	elog "Run kirocrew-desktop as your normal user, not with sudo or as root:"
	elog "a first start as root leaves ~/.config/kirocrew-desktop/ owned"
	elog "by root, and later starts fail with EACCES. To recover:"
	elog "  sudo chown -R \"\${USER}:\${USER}\" ~/.config/kirocrew-desktop"
}

pkg_postrm() {
	xdg_pkg_postrm
}
