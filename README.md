# rato-verlay

A [Gentoo](https://www.gentoo.org/) ebuild repository (overlay) shipping
AWS-related and adjacent packages on `~amd64`: the
[Kiro](https://kiro.dev/) IDE, CLI and Kiro Crew, AWS Systems Manager
agent, CloudWatch agent, EFS mount helper, Amazon DCV server and viewer,
VictoriaMetrics, and the Anthropic Claude Code CLI and desktop app.

This repository contains **Portage-consumable files** - ebuilds,
Manifests, metadata, profiles, and licenses. The CI/CD pipeline that
automates version bumping, testing, and publishing lives in a separate,
private repository (see "How this overlay is updated" below).

## Shipped packages

| Package | Category | Keywords | License | Notes |
|---|---|---|---|---|
| `kiro-bin` | `dev-util` | `~amd64` | `Kiro-EULA` | Kiro desktop IDE under `/opt/kiro` |
| `kiro-cli-bin` | `dev-util` | `~amd64` | `Kiro-CLI-EULA` | Kiro CLI under `/opt/kiro-cli` (3.x: single `kiro-cli` binary; the last five 2.x releases stay available for pinning) |
| `kirocrew-bin` | `dev-util` | `~amd64` | `Apache-2.0` | Kiro Crew desktop app (prebuilt AppImage) under `/opt/kirocrew`, launcher `kirocrew-desktop` |
| `claude-code-bin` | `dev-util` | `~amd64` | `Anthropic-Claude-Terms` | Anthropic Claude Code CLI (prebuilt binary), `claude` |
| `claude-desktop-bin` | `dev-util` | `~amd64` | `Anthropic-Claude-Terms` | Anthropic Claude desktop app (prebuilt, upstream beta for Debian/Ubuntu) |
| `amazon-ssm-agent` | `app-admin` | `~amd64` | `Apache-2.0` | AWS SSM agent, built from Go source |
| `amazon-cloudwatch-agent` | `app-admin` | `~amd64` | `MIT` | CloudWatch agent, built from Go source |
| `amazon-efs-utils-bin` | `net-fs` | `~amd64` | `MIT` | EFS mount helper / `mount.efs`, prebuilt by AWS for AL2023 (works on glibc >= 2.34) |
| `amazon-dcv-server-bin` | `net-misc` | `~amd64` | `NICE-DCV-EULA` | Amazon DCV server (prebuilt binary, multiple yearly releases) |
| `amazon-dcv-viewer-bin` | `net-misc` | `~amd64` | `NICE-DCV-EULA` | Amazon DCV Linux client / viewer (prebuilt binary) |
| `victoria-metrics` | `app-metrics` | `~amd64` | `Apache-2.0` | VictoriaMetrics single-node TSDB, built from Go source |
| `victoria-metrics-bin` | `app-metrics` | `~amd64` | `Apache-2.0` | VictoriaMetrics single-node TSDB, prebuilt official binary |
| `victoria-metrics-cluster` | `app-metrics` | `~amd64` (hard-masked) | `Apache-2.0` | VictoriaMetrics cluster (vminsert + vmselect + vmstorage), built from Go source |
| `victoria-metrics-cluster-bin` | `app-metrics` | `~amd64` (hard-masked) | `Apache-2.0` | VictoriaMetrics cluster, prebuilt official binaries |
| `ssm-user` | `acct-user`, `acct-group` | `~amd64` | `GPL-2` | UID/GID owned by `amazon-ssm-agent` |
| `victoria-metrics` | `acct-user`, `acct-group` | `~amd64` | `GPL-2` | UID/GID owned by `victoria-metrics{,-bin}` |

The daily keeps the newest five ebuilds of every package; Portage
installs the highest version by default, and the oldest kept one is
hard-masked in `profiles/package.mask` (unmask it to pin). The DCV server
ebuilds cover the stable yearly releases 2023-2026, so older hosts can pin
a specific major version via `/etc/portage/package.mask/rato-verlay` if
needed.

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
dev-util/claude-code-bin       Anthropic-Claude-Terms
dev-util/claude-desktop-bin    Anthropic-Claude-Terms
net-misc/amazon-dcv-server-bin NICE-DCV-EULA
net-misc/amazon-dcv-viewer-bin NICE-DCV-EULA
EOF

# Install
emerge --ask dev-util/kiro-cli-bin dev-util/kiro-bin
```

## After install

- `kiro-cli` and `kiro` are symlinked into `/usr/bin/` (Kiro CLI 3.x no
  longer has `kiro-cli-chat` / `kiro-cli-term`; the 2.x ebuilds still
  install them).
- `kiro-bin` and `kirocrew-bin` install an XDG `.desktop` entry and icon;
  run `kirocrew-desktop` as your normal user, not as root.
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

Not shipped by this overlay - the Gentoo tree and kernel provide what
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

1. Reads `packages.toml` from the pipeline repository (the list of
   packages to track, where to look for upstream version data, and the
   expected download URL and release index of each package).
2. Polls each upstream endpoint (GitHub release, custom JSON, RPM
   repository, etc.).
3. For every package whose upstream is newer than the highest in-tree
   ebuild, checks that upstream publishes the expected file (in the
   release index, with its sha256), copies the existing ebuild to the
   new version, checks that it fetches exactly that file, runs
   `pkgdev manifest`, and compares the distfile's sha256 with upstream.
4. Emerges every new or changed ebuild (bumps, and changes on `dev`
   that are not yet on `main`) on the live instance and runs a smoke
   test.
5. Stamps what passed, keeps the newest five ebuilds per package,
   regenerates `metadata/md5-cache`, commits with a noreply identity and
   pushes HEAD to `main`, `dev`, and `test` on CodeCommit.
6. Self-terminates.

A bump that fails in any step is dropped completely (no ebuild, no
Manifest line, no cache entry) and the other packages still go out.
Every failure - and every package that lags upstream for more than three
days - is mailed to the maintainer by every run until it is fixed. If a
change on `dev` itself fails, the daily cascades down to `test`, then
`main`.

### Weekly (Saturday)

After the Saturday daily, the same instance clones the `test` branch
and emerges every ebuild that does not carry a
`# ebuild automatically verified at <date>` stamp yet, then stamps the
ones that pass. The daily stamps every ebuild it publishes, so in
practice the weekly only picks up ebuilds that reached the overlay
without a daily run (it found none since 2026-08-22). A stamp records the
first successful verification; stamped ebuilds are not re-verified.

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
templates, packages.toml, builder scripts) lives in private repositories.

## Repository layout

```
rato-verlay/
├── acct-group/                 # GIDs for ssm-user, victoria-metrics
├── acct-user/                  # UIDs for ssm-user, victoria-metrics
├── app-admin/                  # SSM + CloudWatch agent ebuilds
├── app-metrics/                # VictoriaMetrics (source + bin) ebuilds
├── dev-util/                   # Kiro IDE, CLI, Crew + Claude ebuilds
├── net-fs/                     # amazon-efs-utils-bin ebuild
├── net-misc/                   # DCV server + viewer ebuilds
├── metadata/layout.conf        # Portage repository metadata
├── profiles/                   # repo_name + categories
├── licenses/                   # EULA texts (Kiro, DCV, Anthropic)
├── .github/workflows/          # GitHub Action: sync from CodeCommit
├── LICENSE                     # GPL-2 (overlay scripts only)
└── README.md
```

## Branch policy

This repo has three branches that always converge after a successful
daily run:

- **`main`** - what the public should consume. Every commit reaching
  `main` was either created by an automated daily/weekly run or
  manually verified.
- **`dev`** - the daily's first attempt branch and the entry point for
  hand-written changes. The daily emerges what differs from `main` and
  then pushes the same HEAD to `main` and `test`. On failure it cascades
  down to `test` and then `main`.
- **`test`** - the weekly's verification branch.

History is rewritten on all three branches after large structural
changes (squash, public-release prep) - clone with `--depth=1` if you
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
