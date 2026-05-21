# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-16
EAPI=8

inherit systemd

DESCRIPTION="Fast time-series database (upstream prebuilt static binary)"
HOMEPAGE="https://victoriametrics.com/ https://github.com/VictoriaMetrics/VictoriaMetrics"

# Two upstream release artifacts for v${PV}:
#   * victoria-metrics-linux-amd64-vN.M.P.tar.gz  -> victoria-metrics-prod
#   * vmutils-linux-amd64-vN.M.P.tar.gz           -> vmagent-prod, vmctl-prod,
#                                                    vmbackup-prod, vmrestore-prod,
#                                                    vmalert-prod, vmalert-tool-prod,
#                                                    vmauth-prod
# Both are statically linked Go binaries built by upstream's release
# pipeline. No external runtime dependencies — they only need a Linux
# kernel and a writable storage path.
SRC_URI="
	https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${PV}/victoria-metrics-linux-amd64-v${PV}.tar.gz
	https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${PV}/vmutils-linux-amd64-v${PV}.tar.gz
"
# Upstream tarballs unpack into ${WORKDIR} as a flat list of binaries
# (no top-level directory). Set S so EAPI 8 default src_unpack stays happy.
S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
# strip — Go binaries embed the runtime version in build info; stripping
#   would corrupt --version output.
# mirror — upstream forbids redistribution from Gentoo mirrors.
# bindist — explicitly OSS Apache-2.0, but stay conservative (matches
#   amazon-efs-utils-bin convention for binary repackaging).
RESTRICT="strip mirror"
QA_PREBUILT="opt/victoriametrics/*"

RDEPEND="
	acct-group/victoria-metrics
	acct-user/victoria-metrics
	!!app-metrics/victoria-metrics
"

src_install() {
	# Install layout matches the source-build sibling
	# (app-metrics/victoria-metrics) so the ansible victoriametrics
	# role's systemd override + binary path are package-agnostic.
	exeinto /opt/victoriametrics
	doexe "${WORKDIR}"/victoria-metrics-prod
	doexe "${WORKDIR}"/vmagent-prod
	doexe "${WORKDIR}"/vmctl-prod
	doexe "${WORKDIR}"/vmbackup-prod
	doexe "${WORKDIR}"/vmrestore-prod
	doexe "${WORKDIR}"/vmalert-prod
	doexe "${WORKDIR}"/vmalert-tool-prod
	doexe "${WORKDIR}"/vmauth-prod

	# Convenience symlinks under /usr/bin without the -prod suffix so
	# admins can just type `vmctl ...` etc. The role's healthcheck and
	# the systemd ExecStart line both use /opt/victoriametrics paths,
	# so the symlinks are purely for ergonomics.
	dosym /opt/victoriametrics/victoria-metrics-prod /usr/bin/victoria-metrics
	dosym /opt/victoriametrics/vmagent-prod          /usr/bin/vmagent
	dosym /opt/victoriametrics/vmctl-prod            /usr/bin/vmctl
	dosym /opt/victoriametrics/vmbackup-prod         /usr/bin/vmbackup
	dosym /opt/victoriametrics/vmrestore-prod        /usr/bin/vmrestore
	dosym /opt/victoriametrics/vmalert-prod          /usr/bin/vmalert
	dosym /opt/victoriametrics/vmalert-tool-prod     /usr/bin/vmalert-tool
	dosym /opt/victoriametrics/vmauth-prod           /usr/bin/vmauth

	# Storage path. Mode 0750 so only the service account can read
	# the on-disk format. Owner comes from the acct-user package.
	keepdir /var/lib/victoria-metrics
	fowners victoria-metrics:victoria-metrics /var/lib/victoria-metrics
	fperms 0750 /var/lib/victoria-metrics

	systemd_dounit "${FILESDIR}"/victoria-metrics.service
	keepdir /etc/systemd/system/victoria-metrics.service.d
}

pkg_postinst() {
	elog ""
	elog "VictoriaMetrics ${PV} (upstream prebuilt) is installed."
	elog ""
	elog "  - Binary:        /opt/victoriametrics/victoria-metrics-prod"
	elog "  - Storage:       /var/lib/victoria-metrics (owned by victoria-metrics)"
	elog "  - Systemd unit:  victoria-metrics.service"
	elog ""
	elog "Tune retention/listen/memory via the ansible victoriametrics role"
	elog "(roles/victoriametrics in ansible-playbooks-gentoo). The role drops"
	elog "an override at /etc/systemd/system/victoria-metrics.service.d/."
	elog ""
}
