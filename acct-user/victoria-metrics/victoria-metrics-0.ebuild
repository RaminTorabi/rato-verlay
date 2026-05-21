# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Service account for the victoria-metrics single-node binary.
# Owns /var/lib/victoria-metrics and runs the systemd unit.
inherit acct-user

# Dynamic UID — pinning is unnecessary for this service.
ACCT_USER_ID=-1
ACCT_USER_GROUPS=( victoria-metrics )
# /var/lib/victoria-metrics is created by the app ebuild; this
# user's home doubles as the storage path so any code that
# resolves $HOME for the service finds the right place.
ACCT_USER_HOME=/var/lib/victoria-metrics
ACCT_USER_HOME_OWNER=victoria-metrics:victoria-metrics
ACCT_USER_HOME_PERMS=0750
# No interactive shell — service-only account.
ACCT_USER_SHELL=/sbin/nologin
ACCT_USER_COMMENT="VictoriaMetrics time-series database"

acct-user_add_deps
