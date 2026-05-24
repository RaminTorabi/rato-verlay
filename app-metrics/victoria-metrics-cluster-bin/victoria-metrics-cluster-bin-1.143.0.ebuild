# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit systemd

DESCRIPTION="VictoriaMetrics cluster — prebuilt vminsert+vmselect+vmstorage"
HOMEPAGE="https://victoriametrics.com/ https://github.com/VictoriaMetrics/VictoriaMetrics"

# Single upstream cluster artifact contains all three statically
# linked Go binaries: vminsert-prod, vmselect-prod, vmstorage-prod.
# No external runtime dependencies — they only need a Linux kernel
# and writable storage paths.
SRC_URI="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${PV}/victoria-metrics-linux-amd64-v${PV}-cluster.tar.gz"

# Upstream tarball unpacks into ${WORKDIR} as a flat list of binaries
# (no top-level directory). Set S so EAPI 8 default src_unpack stays
# happy.
S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
# strip — Go binaries embed runtime version in build info; stripping
#   would corrupt --version output.
# mirror — upstream forbids redistribution from Gentoo mirrors.
RESTRICT="strip mirror"
QA_PREBUILT="opt/victoriametrics/*"

RDEPEND="
	acct-group/victoria-metrics
	acct-user/victoria-metrics
	!!app-metrics/victoria-metrics-cluster
"

src_install() {
	# Layout matches the source-build sibling
	# (app-metrics/victoria-metrics-cluster) so the eventual
	# ansible role drop-ins are package-agnostic.
	exeinto /opt/victoriametrics
	doexe "${WORKDIR}"/vminsert-prod
	doexe "${WORKDIR}"/vmselect-prod
	doexe "${WORKDIR}"/vmstorage-prod

	# Convenience symlinks under /usr/bin without the -prod suffix
	# so admins can run `vminsert --version` etc. directly.
	dosym /opt/victoriametrics/vminsert-prod  /usr/bin/vminsert
	dosym /opt/victoriametrics/vmselect-prod  /usr/bin/vmselect
	dosym /opt/victoriametrics/vmstorage-prod /usr/bin/vmstorage

	# Storage path. Cluster uses /var/lib/victoria-metrics/cluster/
	# so it doesn't collide with the single-node sibling's data
	# directory if both ever land on the same host (vmstorage
	# itself further subdirectorises by role inside this path).
	# Mode 0750 so only the service account can read on-disk
	# format.
	keepdir /var/lib/victoria-metrics/cluster
	fowners victoria-metrics:victoria-metrics /var/lib/victoria-metrics/cluster
	fperms 0750 /var/lib/victoria-metrics/cluster

	# Three units, one per role. Files are byte-identical to the
	# source-build sibling — keep both in sync if you edit either
	# (this isn't enforced by tests yet; a `make check-templates`
	# style guard would be nice once we have more sibling pairs).
	systemd_dounit "${FILESDIR}"/vmstorage.service
	systemd_dounit "${FILESDIR}"/vminsert.service
	systemd_dounit "${FILESDIR}"/vmselect.service
	keepdir /etc/systemd/system/vmstorage.service.d
	keepdir /etc/systemd/system/vminsert.service.d
	keepdir /etc/systemd/system/vmselect.service.d
}

pkg_postinst() {
	elog ""
	elog "VictoriaMetrics cluster ${PV} (upstream prebuilt) is installed."
	elog ""
	elog "  - Binaries:      /opt/victoriametrics/{vminsert,vmselect,vmstorage}-prod"
	elog "  - Storage:       /var/lib/victoria-metrics/cluster/ (owned by victoria-metrics)"
	elog "  - Systemd units: vmstorage.service, vminsert.service, vmselect.service"
	elog ""
	elog "Cluster ports (defaults — override via -httpListenAddr in a unit drop-in):"
	elog "  - vmstorage  http :8482   vminsert RPC :8400   vmselect RPC :8401"
	elog "  - vminsert   http :8480   write API at /insert/<accountID>/<suffix>"
	elog "  - vmselect   http :8481   read API  at /select/<accountID>/<suffix>"
	elog ""
	elog "Start order: vmstorage first, then vminsert and vmselect (which dial it)."
	elog "Tune retention, storageNode wiring and replicationFactor via drop-ins under"
	elog "/etc/systemd/system/<unit>.service.d/. The cluster docs are at"
	elog "https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/."
	elog ""
	elog "For deployments below ~1M datapoints/sec the single-node sibling"
	elog "(app-metrics/victoria-metrics{,-bin}) is recommended over the cluster."
	elog ""
}
