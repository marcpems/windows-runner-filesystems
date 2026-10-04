# Standard GitHub-hosted Windows filesystem probe

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
