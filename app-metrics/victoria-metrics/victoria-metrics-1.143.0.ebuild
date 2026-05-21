# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module systemd

DESCRIPTION="Fast, cost-effective monitoring solution and time-series database"
HOMEPAGE="https://victoriametrics.com/ https://github.com/VictoriaMetrics/VictoriaMetrics"
SRC_URI="https://github.com/VictoriaMetrics/VictoriaMetrics/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/VictoriaMetrics-${PV}"

# Apache-2.0 covers the OSS components built from the public GitHub
# tarball. The proprietary "Enterprise" features are NOT compiled in
# from this source — those ship as separate closed-source binaries
# from victoriametrics.com and aren't reachable from this build path.
LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="mirror"

# go.mod requires go 1.26.3+, but the eclass already enforces a current
# go via its own BDEPEND. Override only when we need a higher floor
# than the eclass default. Note: 1.26.3 is currently ~amd64 in the
# Gentoo tree, so emerging this ebuild also pulls in dev-lang/go's
# unstable keyword via the rato-verlay accept_keywords list.
BDEPEND=">=dev-lang/go-1.26.3"

RDEPEND="
	acct-group/victoria-metrics
	acct-user/victoria-metrics
	!!app-metrics/victoria-metrics-bin
"

src_compile() {
	# Upstream ships vendor/ under tag v1.143.0, so the build is
	# fully offline (no network-sandbox lift needed). Use
	# `-mod=vendor` to make Go consume the vendored copies and
	# refuse to fetch from the proxy on cache miss.
	#
	# The buildinfo string surfaces in `victoria-metrics --version`
	# and the /metrics endpoint as vm_app_version; mirroring the
	# upstream Makefile's GO_BUILDINFO format keeps that field
	# parseable by VM's own dashboards.
	local pkg_prefix="github.com/VictoriaMetrics/VictoriaMetrics"
	local buildinfo="-X ${pkg_prefix}/lib/buildinfo.Version=victoria-metrics-${PV}-gentoo"

	ego build -mod=vendor -ldflags "${buildinfo}" -o victoria-metrics ./app/victoria-metrics
	ego build -mod=vendor -ldflags "${buildinfo}" -o vmagent          ./app/vmagent
	ego build -mod=vendor -ldflags "${buildinfo}" -o vmctl            ./app/vmctl
	ego build -mod=vendor -ldflags "${buildinfo}" -o vmbackup         ./app/vmbackup
	ego build -mod=vendor -ldflags "${buildinfo}" -o vmrestore        ./app/vmrestore
}

src_install() {
	# Match the path the role's systemd override expects:
	#   /opt/victoriametrics/victoria-metrics-prod
	exeinto /opt/victoriametrics
	newexe victoria-metrics victoria-metrics-prod
	doexe vmagent vmctl vmbackup vmrestore

	# Convenience symlinks under /usr/bin so admins can run any of
	# these directly without prefixing the install path.
	dosym /opt/victoriametrics/victoria-metrics-prod /usr/bin/victoria-metrics
	dosym /opt/victoriametrics/vmagent               /usr/bin/vmagent
	dosym /opt/victoriametrics/vmctl                 /usr/bin/vmctl
	dosym /opt/victoriametrics/vmbackup              /usr/bin/vmbackup
	dosym /opt/victoriametrics/vmrestore             /usr/bin/vmrestore

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
	elog "VictoriaMetrics ${PV} is installed."
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
