# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# ebuild automatically verified at 2026-05-07
EAPI=8

# User account for AWS Systems Manager Session Manager sessions.
#
# When a Session Manager user connects to the instance, amazon-ssm-agent
# creates local login sessions as the `ssm-user` account (if configured
# to do so in the agent's config, or dynamically at session start).
# The agent WILL create ssm-user on-demand at first session — pre-creating
# it here is not strictly required, but lets us pin a stable UID/GID
# across Base AMI rebuilds and surfaces the account in Portage's
# package database for audit.
#
# See: https://docs.aws.amazon.com/systems-manager/latest/userguide/
#        ssm-agent-technical-details.html#about-ssm-user
inherit acct-user

# Overlay policy: dynamic UID is acceptable. We don't pin a specific
# UID here because there's no well-known AWS-assigned value — the
# upstream packaging just lets /usr/sbin/useradd pick the next system
# UID at install time.
ACCT_USER_ID=-1
ACCT_USER_GROUPS=( ssm-user )
ACCT_USER_HOME=/home/ssm-user
ACCT_USER_HOME_OWNER=ssm-user:ssm-user
ACCT_USER_HOME_PERMS=0700
# Session Manager spawns an interactive shell as ssm-user; bash is
# the idiomatic shell for a login session on Gentoo.
ACCT_USER_SHELL=/bin/bash
ACCT_USER_COMMENT="AWS Systems Manager Session Manager user"

acct-user_add_deps
