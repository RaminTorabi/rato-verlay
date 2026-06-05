# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-30
EAPI=8

inherit go-module systemd

DESCRIPTION="VictoriaMetrics cluster (vminsert + vmselect + vmstorage)"
HOMEPAGE="https://victoriametrics.com/ https://github.com/VictoriaMetrics/VictoriaMetrics"
# Upstream maintains a parallel `vN.M.P-cluster` git tag on the
# cluster branch alongside the single-node `vN.M.P` tag. The cluster
# tag is what we build from; the source tarball name is renamed via
# the `->` mapping so it sorts alongside the binary-variant artifacts
# inside the same Manifest line space.
SRC_URI="
	https://github.com/VictoriaMetrics/VictoriaMetrics/archive/refs/tags/v${PV}-cluster.tar.gz
		-> ${P}.tar.gz
"
S="${WORKDIR}/VictoriaMetrics-${PV}-cluster"

# Apache-2.0 covers the OSS components built from the public GitHub
# tarball. Enterprise cluster components (mTLS, downsampling,
# retention filters, etc.) are NOT compiled in from this source path
# and would require a separate enterprise tarball with a different
# license.
LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="mirror"

# Match the floor enforced in the single-node sibling so the same
# cross-package go-toolchain merge plan applies.
BDEPEND=">=dev-lang/go-1.26.3"

# Cluster shares the service account with the single-node sibling.
# Both variants own files under /var/lib/victoria-metrics/, but
# under non-overlapping subdirectories (single-node uses the dir
# directly, cluster uses /var/lib/victoria-metrics/cluster/<role>/),
# so they can coexist on one host even though that's almost never
# operationally desirable.
#
# The !! blocker against -bin keeps Portage from picking both
# source and prebuilt cluster variants on the same host. There is
# intentionally NO blocker against the single-node sibling — they
# install non-overlapping binary names and unit files, and on the
# rare host where someone wants both available, Portage shouldn't
# get in the way.
RDEPEND="
	acct-group/victoria-metrics
	acct-user/victoria-metrics
	!!app-metrics/victoria-metrics-cluster-bin
"

src_compile() {
	# Upstream ships vendor/ under tag v${PV}-cluster, so build is
	# fully offline (no network sandbox lift needed). Use
	# -mod=vendor so the toolchain refuses to fetch from the proxy
	# on cache miss.
	#
	# The buildinfo string surfaces in `<binary> --version` and on
	# the /metrics endpoint as vm_app_version; the format mirrors
	# upstream's Makefile so VictoriaMetrics's own dashboards parse
	# the field correctly.
	local pkg_prefix="github.com/VictoriaMetrics/VictoriaMetrics"
	local buildinfo="-X ${pkg_prefix}/lib/buildinfo.Version=victoria-metrics-cluster-${PV}-gentoo"

	ego build -mod=vendor -ldflags "${buildinfo}" -o vminsert  ./app/vminsert
	ego build -mod=vendor -ldflags "${buildinfo}" -o vmselect  ./app/vmselect
	ego build -mod=vendor -ldflags "${buildinfo}" -o vmstorage ./app/vmstorage
}

src_install() {
	# Install layout matches the prebuilt sibling so the eventual
	# systemd drop-in overrides are package-agnostic. The binaries
	# live alongside the single-node victoria-metrics-prod under
	# /opt/victoriametrics/.
	exeinto /opt/victoriametrics
	newexe vminsert  vminsert-prod
	newexe vmselect  vmselect-prod
	newexe vmstorage vmstorage-prod

	# Convenience symlinks under /usr/bin — admins can run
	# `vminsert --version` etc. without prefixing the path.
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

	# Three units, one per role. Each ships a sensible default
	# ExecStart (loopback storageNode wiring for vminsert/vmselect
	# so an out-of-the-box `systemctl start` Just Works on a
	# single-host toy setup), and an override drop-in directory
	# under /etc/systemd/system/<unit>.service.d/ for per-host
	# tuning.
	systemd_dounit "${FILESDIR}"/vmstorage.service
	systemd_dounit "${FILESDIR}"/vminsert.service
	systemd_dounit "${FILESDIR}"/vmselect.service
	keepdir /etc/systemd/system/vmstorage.service.d
	keepdir /etc/systemd/system/vminsert.service.d
	keepdir /etc/systemd/system/vmselect.service.d
}

pkg_postinst() {
	elog ""
	elog "VictoriaMetrics cluster ${PV} is installed."
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
