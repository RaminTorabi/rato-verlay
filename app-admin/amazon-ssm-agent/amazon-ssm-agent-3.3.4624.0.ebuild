# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-06-03
EAPI=8

inherit go-module systemd

DESCRIPTION="AWS Systems Manager Agent"
HOMEPAGE="https://github.com/aws/amazon-ssm-agent"
SRC_URI="https://github.com/aws/amazon-ssm-agent/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="mirror network-sandbox"

BDEPEND=">=dev-lang/go-1.25"

RDEPEND="
	sys-libs/glibc
	acct-user/ssm-user
"

# Upstream ships six Go binaries. Previous ebuild only built the
# ssm-agent-worker (labeled `./agent`) and installed it as
# `amazon-ssm-agent`, which caused the real launcher's `-version` flag
# to be unrecognized and the agent to die immediately on startup with
# `failed to find agent identity` because the worker was trying to
# bootstrap itself as if it were the top-level agent process.
#
# See upstream makefile `build-any-%` target — the binaries and their
# source paths match this list exactly.
src_compile() {
	local ldflags="-s -w -X github.com/aws/amazon-ssm-agent/agent/version.Version=${PV}"

	# Top-level launcher (the binary systemd starts).
	ego build -o amazon-ssm-agent -ldflags "${ldflags}" \
		./core

	# Main worker — handles identity, message loop, docs, sessions.
	ego build -o ssm-agent-worker -ldflags "${ldflags}" \
		./agent

	# User-facing CLI.
	ego build -o ssm-cli -ldflags "${ldflags}" \
		./agent/cli-main

	# Out-of-process workers spawned by the main agent.
	ego build -o ssm-document-worker -ldflags "${ldflags}" \
		./agent/framework/processor/executer/outofproc/worker

	ego build -o ssm-session-worker -ldflags "${ldflags}" \
		./agent/framework/processor/executer/outofproc/sessionworker

	ego build -o ssm-session-logger -ldflags "${ldflags}" \
		./agent/session/logging
}

src_install() {
	dobin amazon-ssm-agent
	dobin ssm-agent-worker
	dobin ssm-cli
	dobin ssm-document-worker
	dobin ssm-session-worker
	dobin ssm-session-logger

	# Config templates. The agent at startup copies the `.template`
	# files into the working locations (amazon-ssm-agent.json and
	# seelog.xml) if they don't already exist.
	insinto /etc/amazon/ssm
	newins amazon-ssm-agent.json.template amazon-ssm-agent.json.template
	newins seelog_unix.xml seelog.xml.template

	# Runtime state directories — owned by root, but the agent creates
	# and writes to these during normal operation. Without them pre-
	# created, the agent's `failed to read runtime config` warning
	# escalates into startup failure on some profiles.
	keepdir /var/lib/amazon/ssm
	keepdir /var/lib/amazon/ssm/runtimeconfig
	keepdir /var/log/amazon/ssm
	keepdir /var/log/amazon/ssm/audits

	newinitd "${FILESDIR}"/amazon-ssm-agent.initd amazon-ssm-agent
	systemd_dounit "${FILESDIR}"/amazon-ssm-agent.service
}

pkg_postinst() {
	# Seed the runtime config files from the templates if the agent
	# has never started before. The upstream RPM's %posttrans does
	# this via the `amazon-ssm-agent -register` path, but for a
	# vanilla EC2 boot the agent picks up IMDS automatically from
	# the defaults in the template, so a simple copy is enough.
	if [[ ! -f "${EROOT}/etc/amazon/ssm/amazon-ssm-agent.json" ]] \
		&& [[ -f "${EROOT}/etc/amazon/ssm/amazon-ssm-agent.json.template" ]]; then
		cp "${EROOT}/etc/amazon/ssm/amazon-ssm-agent.json.template" \
			"${EROOT}/etc/amazon/ssm/amazon-ssm-agent.json"
	fi
	if [[ ! -f "${EROOT}/etc/amazon/ssm/seelog.xml" ]] \
		&& [[ -f "${EROOT}/etc/amazon/ssm/seelog.xml.template" ]]; then
		cp "${EROOT}/etc/amazon/ssm/seelog.xml.template" \
			"${EROOT}/etc/amazon/ssm/seelog.xml"
	fi
	elog "amazon-ssm-agent installed."
	elog "Enable with:  systemctl enable --now amazon-ssm-agent"
}
