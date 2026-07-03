# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-09
EAPI=8

inherit rpm

DESCRIPTION="Amazon DCV remote display server + virtual-session X server (prebuilt binary)"
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
QA_PREBUILT="usr/libexec/dcv/* usr/lib64/dcv/* usr/bin/dcv* usr/bin/Xdcv"

# Runtime libraries the prebuilt DCV binaries dlopen/link that are NOT
# bundled under /usr/lib64/dcv:
#   sys-libs/libselinux         libselinux.so.1 - dcvserver hard-links it;
#                               without it the server aborts on start.
#   media-libs/gst-plugins-base libgsttag-1.0.so.0 - pulled in transitively
#                               by DCV's bundled gstreamer libs.
#   dev-libs/glib               glib-compile-schemas (pkg_postinst) + the
#                               GSettings runtime the server needs.
RDEPEND="
	sys-libs/glibc
	x11-libs/libX11
	x11-libs/libXext
	media-libs/mesa
	sys-libs/libselinux
	media-libs/gst-plugins-base
	dev-libs/glib
"

S="${WORKDIR}"

src_unpack() {
	default
	# The tarball contains several RPMs. We need the server (the daemon +
	# wrappers + libs + systemd unit + dbus policy + PAM stack + GSettings
	# schemas) and nice-xdcv (the Xdcv virtual X server, required for
	# headless virtual sessions - without it every `create-session
	# --type=virtual` dies with "Script terminated during startup").
	local pkg rpm
	for pkg in nice-dcv-server nice-xdcv; do
		rpm=$(find "${WORKDIR}" -name "${pkg}-*.x86_64.rpm" -print -quit)
		[[ -n ${rpm} ]] || die "Could not find ${pkg} RPM in tarball"
		rpm_unpack "${rpm}"
	done
}

src_install() {
	# The nice-dcv-server / nice-xdcv RPMs already lay every file out under
	# the FHS prefixes that DCV's own wrapper scripts (/usr/bin/dcv*,
	# /usr/bin/Xdcv) hardcode:
	#
	#   /usr/libexec/dcv/        backend ELF binaries (dcvserver, dcvagent,
	#                            dcvsessionstarter, dcvpamhelper, ...)
	#   /usr/bin/Xdcv            virtual-session X server (nice-xdcv)
	#   /usr/lib64/dcv/          private shared libraries + modules
	#   /usr/bin/dcv*            wrapper scripts (reference the paths above
	#                            via programsdir=/usr/libexec/dcv and
	#                            pkglibdir=/usr/lib64/dcv)
	#   /etc/dcv/                dcv.conf + default config + dcvsessioninit
	#   /etc/pam.d/dcv           PAM stack for the default "system" auth
	#   /etc/dbus-1/system.d/    com.nicesoftware.DcvServer.conf policy
	#   /usr/share/glib-2.0/schemas/  com.nicesoftware.dcv.* GSettings schemas
	#   /usr/lib/systemd/system/dcvserver.service (+ dcvsessionlauncher)
	#
	# Install the extracted tree verbatim - relocating any of it (as an
	# earlier revision did under /opt) breaks the wrappers and drops the
	# backend binaries, unit, dbus policy, PAM stack, and schemas.
	local d
	for d in usr etc opt lib; do
		[[ -d ${d} ]] || continue
		cp -a "${d}" "${ED}/" || die "failed to install /${d} tree"
	done

	[[ -f "${ED}/usr/libexec/dcv/dcvserver" ]] \
		|| die "dcvserver backend binary missing after install - RPM layout changed"
	[[ -f "${ED}/usr/bin/Xdcv" ]] \
		|| die "Xdcv missing after install - virtual sessions would fail"

	# dcvpamhelper validates passwords through PAM on behalf of the
	# unprivileged dcvserver; it MUST be setuid root or "system" auth fails.
	# (rpm2targz does not preserve the RPM's %attr(4755) bit.)
	fperms 4755 /usr/libexec/dcv/dcvpamhelper

	# Persistent state + per-session log dirs. /run/dcv is handled at
	# runtime by the unit's RuntimeDirectory=; these two are persistent.
	keepdir /var/lib/dcv /var/log/dcv
}

pkg_postinst() {
	# Create the dcv service account (equivalent of the RPM's %pre
	# scriptlet, which rpm_unpack does not run). dcvserver.service runs as
	# User=dcv/Group=dcv, so without this it fails with 217/USER.
	if ! getent group dcv >/dev/null 2>&1; then
		groupadd -r dcv || ewarn "failed to create group 'dcv'"
	fi
	if ! getent passwd dcv >/dev/null 2>&1; then
		useradd -r -g dcv -d /var/lib/dcv -s /sbin/nologin -c "Amazon DCV" dcv \
			|| ewarn "failed to create user 'dcv'"
	fi

	chown dcv:dcv "${EROOT}/var/lib/dcv" 2>/dev/null
	# Virtual-session logs are written by the session OWNER (an arbitrary
	# desktop user), not by dcv, so the log dir needs the sticky
	# world-writable mode /tmp uses. Without this, dcvsessionstarter cannot
	# open its per-session log and the session dies during startup.
	chown dcv:dcv "${EROOT}/var/log/dcv" 2>/dev/null
	chmod 1777 "${EROOT}/var/log/dcv" 2>/dev/null

	# DCV ships GSettings schemas (com.nicesoftware.dcv.*); they must be
	# compiled into gschemas.compiled or dcvserver aborts with
	# "Settings schema 'com.nicesoftware.dcv.security' is not installed".
	if type glib-compile-schemas >/dev/null 2>&1; then
		glib-compile-schemas "${EROOT}/usr/share/glib-2.0/schemas" \
			|| ewarn "glib-compile-schemas failed - dcvserver may not start"
	else
		ewarn "glib-compile-schemas not found; run it against"
		ewarn "  ${EROOT}/usr/share/glib-2.0/schemas before starting dcvserver"
	fi

	elog "Amazon DCV installed. Enable the server with:"
	elog "    systemctl enable --now dcvserver.service"
	elog "Headless (no GPU) virtual desktop session:"
	elog "    dcv create-session --type=virtual --owner <user> <name>"
	elog "The DBus policy in /etc/dbus-1/system.d is read by dbus at boot;"
	elog "on a running system reload it with:"
	elog "    dbus-send --system --type=method_call --dest=org.freedesktop.DBus \\"
	elog "        / org.freedesktop.DBus.ReloadConfig"
}
