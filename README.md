# rato-verlay

A [Gentoo](https://www.gentoo.org/) ebuild repository (overlay) shipping
AWS-related and adjacent packages on `~amd64`: the
[Kiro](https://kiro.dev/) IDE and CLI suite, AWS Systems Manager agent,
CloudWatch agent, EFS mount helper, Amazon DCV server and viewer, and
VictoriaMetrics.

This repository contains **Portage-consumable files** — ebuilds,
Manifests, metadata, profiles, and licenses. The CI/CD pipeline that
automates version bumping, testing, and publishing lives in a separate
repository:
[rato-verlay-pipeline](https://github.com/RaminTorabi/rato-verlay-pipeline).

## Shipped packages

| Package | Category | Keywords | License | Notes |
|---|---|---|---|---|
| `kiro-bin` | `dev-util` | `~amd64` | `Kiro-EULA` | Kiro desktop IDE under `/opt/kiro` |
| `kiro-cli-bin` | `dev-util` | `~amd64` | `Kiro-CLI-EULA` | Kiro CLI suite under `/opt/kiro-cli` |
| `amazon-ssm-agent` | `app-admin` | `~amd64` | `Apache-2.0` | AWS SSM agent, built from Go source |
| `amazon-cloudwatch-agent` | `app-admin` | `~amd64` | `MIT` | CloudWatch agent, built from Go source |
| `amazon-efs-utils-bin` | `net-fs` | `~amd64` | `MIT` | EFS mount helper / `mount.efs`, prebuilt by AWS for AL2023 (works on glibc >= 2.34) |
| `amazon-dcv-server-bin` | `net-misc` | `~amd64` | `NICE-DCV-EULA` | Amazon DCV server (prebuilt binary, multiple yearly releases) |
| `amazon-dcv-viewer-bin` | `net-misc` | `~amd64` | `NICE-DCV-EULA` | Amazon DCV Linux client / viewer (prebuilt binary) |
| `victoria-metrics` | `app-metrics` | `~amd64` | `Apache-2.0` | VictoriaMetrics single-node TSDB, built from Go source |
| `victoria-metrics-bin` | `app-metrics` | `~amd64` | `Apache-2.0` | VictoriaMetrics single-node TSDB, prebuilt official binary |
| `ssm-user` | `acct-user`, `acct-group` | `~amd64` | `GPL-2` | UID/GID owned by `amazon-ssm-agent` |
| `victoria-metrics` | `acct-user`, `acct-group` | `~amd64` | `GPL-2` | UID/GID owned by `victoria-metrics{,-bin}` |

Multiple versions are available for `amazon-ssm-agent`,
`amazon-cloudwatch-agent`, `kiro-bin`, `kiro-cli-bin`, and
`amazon-dcv-server-bin`. Portage installs the highest version by
default. The DCV server overlay ships one ebuild per stable yearly
release (2021-2025) so older hosts can pin to a specific major version
via `/etc/portage/package.mask/rato-verlay` if needed. The DCV viewer
ships only the latest stable release — viewer releases are infrequent.

## Quick start

```sh
# Install eselect-repository if not already present
emerge --ask app-eselect/eselect-repository

# Add the overlay
eselect repository add rato-verlay git https://github.com/RaminTorabi/rato-verlay.git

# Sync
emerge --sync rato-verlay

# Accept keywords and licenses (per-package)
cat >> /etc/portage/package.accept_keywords/rato-verlay <<'EOF'
*/*::rato-verlay ~amd64
EOF

cat >> /etc/portage/package.license/rato-verlay <<'EOF'
dev-util/kiro-bin              Kiro-EULA
dev-util/kiro-cli-bin          Kiro-CLI-EULA
net-misc/amazon-dcv-server-bin NICE-DCV-EULA
net-misc/amazon-dcv-viewer-bin NICE-DCV-EULA
EOF

# Install
emerge --ask dev-util/kiro-cli-bin dev-util/kiro-bin
```

## After install

- `kiro-cli`, `kiro-cli-chat`, `kiro-cli-term`, and `kiro` are
  symlinked into `/usr/bin/`.
- `kiro-bin` installs an XDG `.desktop` entry and icon.
- `amazon-ssm-agent`, `amazon-cloudwatch-agent`, and
  `victoria-metrics{,-bin}` install with systemd service files.
- `amazon-efs-utils-bin` installs `mount.efs` and the
  `amazon-efs-mount-watchdog.service` unit. Enable the watchdog before
  using TLS mounts:
  ```sh
  systemctl enable --now amazon-efs-mount-watchdog.service
  mount -t efs -o tls fs-XXXXXXXX:/ /mnt/efs
  ```
- `amazon-dcv-server-bin` installs under `/opt/amazon-dcv/` with
  `dcv` symlinked into `/usr/bin/`.
- `amazon-dcv-viewer-bin` installs under `/opt/amazon-dcv-viewer/`
  with `dcvviewer` symlinked into `/usr/bin/`. The viewer bundles its
  own GTK4 / GStreamer libraries so it does not collide with system
  libs.

To connect to a DCV server:

```sh
dcvviewer dcv://<server-host>:<port>/<session-id>
```

Smoke test:

```sh
kiro-cli --version
amazon-ssm-agent --version
amazon-cloudwatch-agent --version
```

## AWS networking helpers

Not shipped by this overlay — the Gentoo tree and kernel provide what
is needed.

### Elastic Fabric Adapter (EFA)

The EFA provider is part of upstream libfabric and available in the
Gentoo tree as `sys-block/libfabric` with the `efa` USE flag:

```sh
echo "sys-block/libfabric efa" >> /etc/portage/package.use/libfabric
emerge --ask sys-block/libfabric
```

### FSx for Lustre

The Lustre client is a **kernel module**. To mount an FSx for Lustre
filesystem from a Gentoo instance, build the client from source:

```sh
# Install build dependencies
emerge --ask sys-kernel/linux-headers sys-devel/bc

# Clone and build (client only, no server modules)
git clone https://github.com/lustre/lustre-release.git
cd lustre-release
git checkout 2.16.0  # match your FSx filesystem version
sh autogen.sh
./configure --disable-server --with-linux=/usr/src/linux
make -j$(nproc)
make install
```

Mount:

```sh
modprobe lustre
mount -t lustre <fsx-dns-name>@tcp:/<mount-name> /mnt/fsx
```

The kernel module must be rebuilt after every kernel update.

## How this overlay is updated

The pipeline runs entirely in AWS and is split across two cadences:

### Daily (every 24h)

A scheduled Lambda boots an EC2 instance off a pre-built Gentoo Update
AMI. The instance:

1. Reads `packages.toml` from `rato-verlay-pipeline` (the list of
   packages to track and where to look for upstream version data).
2. Polls each upstream endpoint (GitHub release, custom JSON, etc.).
3. For every package whose upstream is newer than the highest in-tree
   ebuild, copies the existing ebuild to the new version, stamps the
   new release, and runs `pkgdev manifest` to refresh hashes.
4. Validates the bump by emerging every version of the package
   (oldest to newest) on the live instance and running a smoke test.
5. On success, commits the new ebuilds with a noreply identity and
   force-pushes HEAD to `main`, `dev`, and `test` on CodeCommit.
6. Self-terminates.

If validation on the `dev` branch fails, the daily cascades down to
`test`, then `main`, attempting the same bump against each ancestor
state until one succeeds. If all three fail, the run reports failure
via SES and writes a completion JSON to S3 with the per-branch error
trail; nothing is pushed.

### Weekly (Saturday)

A separate orchestration boots a Test-AMI instance, clones the
`test` branch, and verifies every ebuild in the overlay still
emerges cleanly (full `version_cycle_emerge` per package). Each
verified ebuild gets a `# ebuild automatically verified at <date>`
stamp. The squashed result is pushed to `dev` for cascade promotion;
on a fully clean run it propagates to `test` and then to `main`.

### GitHub mirror

A scheduled GitHub Action ([`sync-from-codecommit.yml`](./.github/workflows/sync-from-codecommit.yml))
runs at 05:00 UTC. It assumes a CodeCommit-pull IAM role via OIDC,
fetches `main`, `dev`, and `test` from CodeCommit, and pushes each
branch to this GitHub repository. Branches with a fast-forward
relationship are FF-pushed; divergent branches (after a weekly
squash, for example) are pushed with `--force-with-lease` so the
mirror cannot lose work. The action can also be triggered manually
via `workflow_dispatch`.

Pipeline infrastructure (Lambda code, IAM, CloudFormation/SAM
templates, packages.toml, builder scripts) lives in
[rato-verlay-pipeline](https://github.com/RaminTorabi/rato-verlay-pipeline).

## Repository layout

```
rato-verlay/
├── acct-group/                 # GIDs for ssm-user, victoria-metrics
├── acct-user/                  # UIDs for ssm-user, victoria-metrics
├── app-admin/                  # SSM + CloudWatch agent ebuilds
├── app-metrics/                # VictoriaMetrics (source + bin) ebuilds
├── dev-util/                   # Kiro IDE + CLI ebuilds
├── net-fs/                     # amazon-efs-utils-bin ebuild
├── net-misc/                   # DCV server + viewer ebuilds
├── metadata/layout.conf        # Portage repository metadata
├── profiles/                   # repo_name + categories
├── licenses/                   # EULA texts (Kiro, DCV)
├── .github/workflows/          # GitHub Action: sync from CodeCommit
├── LICENSE                     # GPL-2 (overlay scripts only)
└── README.md
```

## Branch policy

This repo has three branches that always converge after a successful
daily run:

- **`main`** — what the public should consume. Every commit reaching
  `main` was either created by an automated daily/weekly run or
  manually verified.
- **`dev`** — the daily's first attempt branch. On success the daily
  pushes the same HEAD to `main` and `test` in addition to `dev`. On
  failure it cascades down to `test` and then `main`.
- **`test`** — the weekly's verification branch. Holds the squashed
  per-package stamps once the weekly has emerged every ebuild end-to-
  end on a real Gentoo instance.

History is rewritten on all three branches after large structural
changes (squash, public-release prep) — clone with `--depth=1` if you
want a current snapshot, or accept that `git pull` may need a `--rebase`
or fresh clone after such events. Tags will be added to mark stable
points if there is demand.

## Licensing

Ebuild scripts, metadata, and documentation are licensed under
**GPL-2** (see [`LICENSE`](./LICENSE)). Upstream distfiles fetched via
`SRC_URI` are governed by their respective licenses shipped under
`licenses/`.

## Further reading

- [Ebuild repository / Local overlay](https://wiki.gentoo.org/wiki/Ebuild_repository/Local_overlay)
- [eselect/Repository](https://wiki.gentoo.org/wiki/Eselect/Repository)
- [Repository format](https://wiki.gentoo.org/wiki/Repository_format)

## Reporting issues

File issues and pull requests against
[`RaminTorabi/rato-verlay`](https://github.com/RaminTorabi/rato-verlay)
on GitHub.
