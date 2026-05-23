# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-07
EAPI=8

inherit go-module systemd

DESCRIPTION="Amazon CloudWatch Agent for metrics and logs collection"
HOMEPAGE="https://github.com/aws/amazon-cloudwatch-agent"
SRC_URI="https://github.com/aws/amazon-cloudwatch-agent/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="mirror network-sandbox"

BDEPEND=">=dev-lang/go-1.25"

RDEPEND="
	sys-libs/glibc
"

src_compile() {
	# Main agent binary
	ego build -o amazon-cloudwatch-agent \
		-ldflags "-s -w -X github.com/aws/amazon-cloudwatch-agent/cfg/agentinfo.VersionStr=${PV}" \
		./cmd/amazon-cloudwatch-agent

	# Config translator (required for agent startup)
	ego build -o config-translator \
		-ldflags "-s -w" \
		./cmd/config-translator

	# Start wrapper
	ego build -o start-amazon-cloudwatch-agent \
		-ldflags "-s -w" \
		./cmd/start-amazon-cloudwatch-agent

	# Config downloader
	ego build -o config-downloader \
		-ldflags "-s -w" \
		./cmd/config-downloader
}

src_install() {
	# AWS's upstream packaging expects every binary under
	# /opt/aws/amazon-cloudwatch-agent/bin/. The ctl wrapper, the
	# start-amazon-cloudwatch-agent script, and our own user-data
	# scripts all resolve binaries via that path. Installing into
	# /usr/bin (via dobin) broke the ctl wrapper's config-downloader
	# invocation and forced us to hack around it.
	#
	# Mirror the upstream layout so the ctl / fetch-config / translator
	# flows work out of the box.
	local opt_bin=/opt/aws/amazon-cloudwatch-agent/bin
	exeinto "${opt_bin}"
	doexe amazon-cloudwatch-agent
	doexe config-translator
	doexe start-amazon-cloudwatch-agent
	doexe config-downloader

	# amazon-cloudwatch-agent-ctl is a shell script, not a Go binary.
	newexe packaging/dependencies/amazon-cloudwatch-agent-ctl amazon-cloudwatch-agent-ctl

	# Backward-compat symlinks in /usr/bin so `command -v amazon-cloudwatch-agent`
	# still finds the binary (used by smoke tests and by the existing
	# builder-scripts that grep for PATH-resolvable binaries).
	dosym "${opt_bin}/amazon-cloudwatch-agent" /usr/bin/amazon-cloudwatch-agent
	dosym "${opt_bin}/amazon-cloudwatch-agent-ctl" /usr/bin/amazon-cloudwatch-agent-ctl

	newinitd "${FILESDIR}"/amazon-cloudwatch-agent.initd amazon-cloudwatch-agent
	systemd_dounit "${FILESDIR}"/amazon-cloudwatch-agent.service

	# Config live under /opt/aws/amazon-cloudwatch-agent/etc/ (upstream
	# layout). The start wrapper reads /etc/amazon/... first then falls
	# back to the /opt/aws/... path - we install the common config
	# under the /opt/aws tree so both paths work and there's no
	# duplication.
	insinto /opt/aws/amazon-cloudwatch-agent/etc
	newins cfg/commonconfig/common-config.toml common-config.toml

	# Runtime state directories. The agent's start-amazon-cloudwatch-agent
	# wrapper does `chown` on these at startup; if they don't exist it
	# aborts with "lstat .../var: no such file or directory".
	keepdir /opt/aws/amazon-cloudwatch-agent/var
	keepdir /opt/aws/amazon-cloudwatch-agent/logs

	# Legacy path kept for code that hard-codes /etc/amazon/... (e.g.
	# some Amazon docs, DCV, kiro scripts).
	insinto /etc/amazon/amazon-cloudwatch-agent
	newins cfg/commonconfig/common-config.toml common-config.toml
}
