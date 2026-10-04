## windows-latest / sample 1

Image: win25-vs2026 / 20260925.250.1; architecture: X64

| Drive | Filesystem | Label | Size GiB | Free GiB | Allocation unit |
|---|---|---|---:|---:|---:|
|  | FAT32 |  | 0.09 | 0.06 | 512 |
|  | NTFS | Recovery | 0.44 | 0.42 | 4096 |
| C | NTFS | Windows | 149.45 | 32.28 | 4096 |
| D | NTFS | Temporary Storage | 150 | 147.01 | 4096 |

| Environment variable | Path | Filesystem |
|---|---|---|
| GITHUB_WORKSPACE | D:\a\windows-runner-filesystems\windows-runner-filesystems | NTFS |
| RUNNER_TEMP | D:\a\_temp | NTFS |
| RUNNER_TOOL_CACHE | C:\hostedtoolcache\windows | NTFS |
| TEMP | C:\Users\RUNNER~1\AppData\Local\Temp | NTFS |
| USERPROFILE | C:\Users\runneradmin | NTFS |

Successful write/read checks: 4 / 4.
Full disk/partition inventory and fsutil command outputs are in the artifact.
A nonzero devdrv query exit code is diagnostic, not proof that ReFS is unsupported.
