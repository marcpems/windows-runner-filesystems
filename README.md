# Standard GitHub-hosted Windows filesystem probe

## Results: 2026-10-04

**Every mounted working drive observed was NTFS, not ReFS.** All six standard
Windows labels were tested in two workflow runs, with two jobs per label per run:
24 runner instances in total. All 88 small write/read/delete checks succeeded.
The [corrected validation run](https://github.com/marcpems/windows-runner-filesystems/actions/runs/37202732960)
passed all 12 jobs.

| Runner label | Architecture | C: filesystem / volume size | D: filesystem / volume size | Workspace and runner temp |
|---|---|---|---|---|
| `windows-2022` | x64 | NTFS / 255.45 GiB | NTFS / 150.00 or 219.98 GiB | D: |
| `windows-2025` | x64 | NTFS / 149.45 GiB | NTFS / 150.00 or 219.98 GiB | D: |
| `windows-2025-vs2026` | x64 | NTFS / 149.45 GiB | NTFS / 150.00 or 219.98 GiB | D: |
| `windows-latest` | x64 | NTFS / 149.45 GiB | NTFS / 150.00 or 219.98 GiB | D: |
| `windows-11-arm` | Arm64 | NTFS / 255.45 GiB | Not mounted; no D: | C: |
| `windows-11-vs2026-arm` | Arm64 | NTFS / 255.45 GiB | Not mounted; no D: | C: |

Sizes above are filesystem volume capacities, not free space or contractual
allocations. GiB means 1,073,741,824 bytes.

### Important storage details

- **Arm64 has additional raw storage in every sample:** an online, writable
  220 GiB NVMe disk, reported with `PartitionStyle = RAW`, with no partitions,
  filesystem, or drive letter. It is not a preconfigured NTFS/ReFS drive and
  cannot be used as a normal directory without initialization/formatting. This
  probe deliberately did not modify it, so successful ReFS provisioning on it
  has not been tested.
- **The x64 temporary disk varies even within one label/image version:**
  the 150 GiB variant is presented as SAS with MBR partitioning; the 220 GiB
  variant as NVMe with GPT partitioning. Both were NTFS. Do not assume a fixed
  disk number, capacity, partition style, or bus type from `runs-on`.
- All mounted C:/D: volumes reported **NTFS 3.1**, **4,096-byte allocation
  units**, 512-byte logical sectors, and 4,096-byte physical sectors.
- Each OS disk also has an unlettered FAT32 EFI volume, an unlettered NTFS
  recovery volume, and a Microsoft Reserved partition. No ReFS volumes appeared
  anywhere in the volume inventory; "everything is NTFS" would nevertheless be
  inaccurate because EFI uses FAT32.
- All samples had the tool cache at `C:\hostedtoolcache\windows` and the regular
  Windows `TEMP` on C:. `RUNNER_TEMP` was `D:\a\_temp` on x64 and `C:\a\_temp`
  on Arm64; these are not necessarily the same location as `TEMP`.
- Observed C: free space was 79.86-82.77 GiB on Server 2022, 29.18-32.28 GiB on
  Server 2025, and 124.07-124.14 GiB on Arm64. D: had about 147 GiB free on
  the 150 GiB variant, or about 219.87 GiB on the 220 GiB variant.

### ReFS versus Dev Drive

On Server 2025 and Windows 11 Arm64, `fsutil devdrv query` returned:

```text
Developer volumes are enabled.
Developer volumes are protected by antivirus filter.
```

However, querying each mounted drive returned:

```text
This is not a developer volume.
```

Thus **Dev Drive feature availability does not mean the default workspace is
ReFS**. On Server 2022, `fsutil devdrv` was not a recognized command; this does
not by itself establish whether ordinary ReFS volumes can be created.
Creating ReFS volumes or Dev Drives is outside this default-layout test.
See [Microsoft's Dev Drive documentation](https://learn.microsoft.com/en-us/windows/dev-drive/)
for the distinction and provisioning requirements.

### Exact images observed

| Labels | ImageOS | ImageVersion | OS build |
|---|---|---|---|
| `windows-2022` | `win22` | `20260927.320.1` | 20348 |
| `windows-2025`, `windows-2025-vs2026`, `windows-latest` | `win25-vs2026` | `20260925.250.1` | 26100 |
| `windows-11-arm`, `windows-11-vs2026-arm` | `win11-vs2026-arm64` | `20260924.168.1` | 26200 |

Both Arm64 labels resolved to the same image in these runs, as did all three
Server 2025 labels. OS architecture was checked independently of the label.

### Evidence and confidence

- [Initial run](https://github.com/marcpems/windows-runner-filesystems/actions/runs/37202649194)
  and [committed raw evidence](results/37202649194): all filesystem and file IO
  measurements succeeded. The two Server 2022 jobs were marked failed because
  Actions propagated the unsupported diagnostic `fsutil devdrv` exit code.
- [Corrected run](https://github.com/marcpems/windows-runner-filesystems/actions/runs/37202732960)
  and [committed raw evidence](results/37202732960): all 12 jobs passed.
  The fix preserves diagnostic exit codes in JSON, explicitly verifies agreement
  among `Get-Volume`, `Win32_LogicalDisk`, and `fsutil fsinfo volumeinfo`, and exits
  successfully only after required checks pass.

Confidence is high for the configuration actually measured, across every current
standard Windows label in a public repository. It is not a statistical guarantee
about every host in GitHub's fleet, future image releases, or private/larger/custom
runners. The x64 capacity variation is direct evidence that labels do not pin
hardware. GitHub's documented standard storage allocation is 14 GB; these larger
observed volumes should not be treated as a guaranteed entitlement.

Use `GITHUB_WORKSPACE` and `RUNNER_TEMP`, not hard-coded C:/D: assumptions, for
portable workflows. Query the filesystem at runtime if ReFS is a requirement.

## Probe design

Measures default storage on every standard public-repository Windows runner label
listed by GitHub on 2026-10-04, with two independently provisioned jobs per label:

- x64: `windows-2022`, `windows-2025`, `windows-2025-vs2026`, `windows-latest`
- Arm64: `windows-11-arm`, `windows-11-vs2026-arm`

The workflow records image versions, architecture, disk/partition/volume inventory,
filesystem and allocation-unit sizes, capacity and free space, workspace/temp/tool
cache locations, and raw `fsutil` filesystem and Dev Drive query output. It
cross-checks PowerShell and CIM filesystem identification and performs a 4 KiB
write/read/delete check on each mounted fixed drive, the workspace, and runner temp.

No drive is formatted, resized, or mounted, and no custom ReFS volume is created.
Checkout and standard Actions setup occur before measurement; free space is
therefore a snapshot, not a promised capacity. Diagnostic `fsutil` commands preserve
their exit codes, including unsupported Dev Drive queries. ReFS and Dev Drive are
not synonymous: a ReFS volume need not be configured as a Dev Drive.

## Reproduce

Run **Windows default filesystem probe** from the repository's Actions tab using
`workflow_dispatch`, or push a change to the workflow or probe script. Each job
publishes a summary and a `storage-<label>-<sample>` artifact with `storage.json`
and `summary.md` (90-day retention).

This measures standard runners in a public repository, not private-repository
hardware allocations, larger runners, self-hosted runners, or custom images.
Repeated observations establish the sampled configuration, not a guarantee that
GitHub will never change an image or supply another configuration.

## Official references

- [Hosted runner specifications and filesystem path guidance](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Current image labels](https://github.com/actions/runner-images#available-images)
- [Windows Server 2025 D: drive restoration](https://github.com/actions/runner-images/issues/12744)
- [Request to format the temporary/build disk as ReFS](https://github.com/actions/runner-images/issues/8698)
