# rato-verlay

A [Gentoo](https://www.gentoo.org/) ebuild repository (overlay) shipping
AWS-related packages on `~amd64`: the [Kiro](https://kiro.dev/) IDE and
CLI suite, AWS Systems Manager agent, CloudWatch agent, and Amazon DCV
server and viewer.

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
| `amazon-dcv-server-bin` | `net-misc` | `~amd64` | `NICE-DCV-EULA` | Amazon DCV server (prebuilt binary, multiple versions) |
| `amazon-dcv-viewer-bin` | `net-misc` | `~amd64` | `NICE-DCV-EULA` | Amazon DCV Linux client / viewer (prebuilt binary) |

Multiple versions are available for SSM, CloudWatch, and DCV server.
Portage will install the highest version by default. The DCV server
overlay ships one ebuild per stable yearly release (2021-2025) so older
hosts can pin to a specific major version via
`/etc/portage/package.mask/rato-verlay` if needed. The DCV viewer ships
only the latest stable release — new viewer versions land much less
often than server versions.

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
dev-util/kiro-bin              ~amd64
dev-util/kiro-cli-bin          ~amd64
app-admin/amazon-ssm-agent     ~amd64
app-admin/amazon-cloudwatch-agent ~amd64
net-misc/amazon-dcv-server-bin ~amd64
net-misc/amazon-dcv-viewer-bin ~amd64
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
- `amazon-ssm-agent` and `amazon-cloudwatch-agent` install with
  systemd service files.
- `amazon-dcv-server-bin` installs under `/opt/amazon-dcv/` with
  `dcv` symlinked into `/usr/bin/`.
- `amazon-dcv-viewer-bin` installs under `/opt/amazon-dcv-viewer/`
  with `dcvviewer` symlinked into `/usr/bin/`. The viewer bundles its
  own GTK4 / GStreamer libraries to avoid clashing with the system.

To connect to a DCV server:

```sh
dcvviewer dcv://<server-host>:<port>/<session-id>
```

Smoke test:

```sh
kiro-cli --version
kiro --version
amazon-ssm-agent --version
```

## AWS networking

Not shipped by this overlay — the Gentoo tree and kernel provide the
necessary support.

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

A daily AWS Lambda polls upstream release endpoints. When a new version
is detected the Lambda creates the ebuild, downloads the distfile,
computes BLAKE2B/SHA512 hashes, and commits the changes to an
`auto/update-*` branch on CodeCommit. A CodeBuild project then tests
the install on a real Gentoo EC2 instance. If tests pass, the branch is
merged to `main`. A GitHub Action syncs from CodeCommit to this GitHub
repository daily.

Pipeline infrastructure and documentation live in
[rato-verlay-pipeline](https://github.com/RaminTorabi/rato-verlay-pipeline).

## Repository layout

```
rato-verlay/
├── app-admin/                  # SSM + CloudWatch agent ebuilds
├── dev-util/                   # Kiro IDE + CLI ebuilds
├── net-misc/                   # DCV server + DCV viewer ebuilds
├── metadata/layout.conf        # Portage repository metadata
├── profiles/                   # repo_name + categories
├── licenses/                   # EULA texts (Kiro, DCV)
├── .github/workflows/          # GitHub Action: sync from CodeCommit
├── LICENSE                     # GPL-2 (overlay code only)
└── README.md
```

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
