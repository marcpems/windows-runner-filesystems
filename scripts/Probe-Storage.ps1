$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Fsutil {
    param([string[]]$Arguments)
    $output = & fsutil.exe @Arguments 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{
        Command = "fsutil.exe $($Arguments -join ' ')"
        ExitCode = $code
        Output = ($output | Out-String).Trim()
    }
}

function Test-FileIO {
    param([string]$Directory)
    $path = Join-Path $Directory "github-storage-probe-$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $bytes = [byte[]]::new(4096)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        [System.IO.File]::WriteAllBytes($path, $bytes)
        $actual = [System.IO.File]::ReadAllBytes($path)
        if ([Convert]::ToBase64String($bytes) -ne [Convert]::ToBase64String($actual)) {
            throw "Read-back mismatch for $path"
        }
        [pscustomobject]@{ Directory = $Directory; Success = $true; Bytes = $bytes.Length; Error = $null }
    } catch {
        Write-Warning "File IO probe failed for ${Directory}: $_"
        [pscustomobject]@{ Directory = $Directory; Success = $false; Bytes = 0; Error = $_.ToString() }
    } finally {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

$volumes = @(Get-Volume | Sort-Object DriveLetter | Select-Object DriveLetter,
    FileSystem, FileSystemType, FileSystemLabel, DriveType, HealthStatus,
    OperationalStatus, Size, SizeRemaining, AllocationUnitSize, Path, UniqueId)
$disks = @(Get-Disk | Sort-Object Number | Select-Object Number, FriendlyName,
    BusType, PartitionStyle, Size, IsBoot, IsSystem, IsOffline, IsReadOnly)
$partitions = @(Get-Partition | Sort-Object DiskNumber, PartitionNumber |
    Select-Object DiskNumber, PartitionNumber, DriveLetter, Type, Size, Offset,
        IsBoot, IsSystem, IsHidden, AccessPaths)
$logicalDisks = @(Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID,
    DriveType, FileSystem, VolumeName, Size, FreeSpace)
$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$paths = @(
    [pscustomobject]@{ Name = 'GITHUB_WORKSPACE'; Value = $env:GITHUB_WORKSPACE }
    [pscustomobject]@{ Name = 'RUNNER_TEMP'; Value = $env:RUNNER_TEMP }
    [pscustomobject]@{ Name = 'RUNNER_TOOL_CACHE'; Value = $env:RUNNER_TOOL_CACHE }
    [pscustomobject]@{ Name = 'TEMP'; Value = $env:TEMP }
    [pscustomobject]@{ Name = 'USERPROFILE'; Value = $env:USERPROFILE }
) | ForEach-Object {
    $volume = Get-Volume -FilePath $_.Value
    [pscustomobject]@{
        Name = $_.Name
        Path = $_.Value
        DriveLetter = [string]$volume.DriveLetter
        FileSystem = $volume.FileSystem
        VolumePath = $volume.Path
    }
}
$fsutil = @(
    Invoke-Fsutil -Arguments @('fsinfo', 'drives')
    Invoke-Fsutil -Arguments @('devdrv', 'query')
    foreach ($volume in $volumes | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }) {
        $root = "$($volume.DriveLetter):"
        Invoke-Fsutil -Arguments @('fsinfo', 'volumeinfo', $root)
        Invoke-Fsutil -Arguments @('fsinfo', 'sectorinfo', $root)
        if ($volume.FileSystem -eq 'NTFS') {
            Invoke-Fsutil -Arguments @('fsinfo', 'ntfsinfo', $root)
        } elseif ($volume.FileSystem -eq 'ReFS') {
            Invoke-Fsutil -Arguments @('fsinfo', 'refsinfo', $root)
        }
        Invoke-Fsutil -Arguments @('devdrv', 'query', $root)
    }
)
$io = @(
    $targets = @($volumes | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } |
        ForEach-Object { "$($_.DriveLetter):\" })
    $targets += @($env:GITHUB_WORKSPACE, $env:RUNNER_TEMP)
    foreach ($directory in $targets | Select-Object -Unique) {
        Test-FileIO -Directory $directory
    }
)
$report = [ordered]@{
    SchemaVersion = 1
    TimestampUtc = [datetime]::UtcNow.ToString('o')
    RequestedLabel = $env:PROBE_IMAGE
    Sample = $env:PROBE_SAMPLE
    RunUrl = "https://github.com/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
    Commit = $env:GITHUB_SHA
    RunnerName = $env:RUNNER_NAME
    RunnerArchitecture = $env:RUNNER_ARCH
    OSArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    ProcessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    ImageOS = $env:ImageOS
    ImageVersion = $env:ImageVersion
    OS = $os | Select-Object Caption, Version, BuildNumber, OSArchitecture
    Machine = $computer | Select-Object NumberOfLogicalProcessors, TotalPhysicalMemory, Model
    Volumes = $volumes
    Disks = $disks
    Partitions = $partitions
    LogicalDisks = $logicalDisks
    Paths = @($paths)
    Fsutil = $fsutil
    FileIO = $io
}
$outputDirectory = Join-Path $env:GITHUB_WORKSPACE 'evidence'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$json = $report | ConvertTo-Json -Depth 12
$json | Set-Content -LiteralPath (Join-Path $outputDirectory 'storage.json') -Encoding utf8
Write-Output $json
$summary = @(
    "## $env:PROBE_IMAGE / sample $env:PROBE_SAMPLE"
    ''
    "Image: $env:ImageOS / $env:ImageVersion; architecture: $env:RUNNER_ARCH"
    ''
    '| Drive | Filesystem | Label | Size GiB | Free GiB | Allocation unit |'
    '|---|---|---|---:|---:|---:|'
    foreach ($volume in $volumes) {
        "| $($volume.DriveLetter) | $($volume.FileSystem) | $($volume.FileSystemLabel) | $([math]::Round($volume.Size / 1GB, 2)) | $([math]::Round($volume.SizeRemaining / 1GB, 2)) | $($volume.AllocationUnitSize) |"
    }
    ''
    '| Environment variable | Path | Filesystem |'
    '|---|---|---|'
    foreach ($path in $paths) {
        "| $($path.Name) | $($path.Path) | $($path.FileSystem) |"
    }
    ''
    "Successful write/read checks: $(@($io | Where-Object Success).Count) / $($io.Count)."
    'Full disk/partition inventory and fsutil command outputs are in the artifact.'
    'A nonzero devdrv query exit code is diagnostic, not proof that ReFS is unsupported.'
)
$summary | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.md') -Encoding utf8
$summary | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
if (@($io | Where-Object { -not $_.Success }).Count -gt 0) {
    throw 'One or more write/read checks failed; inspect the recorded errors.'
}
foreach ($disk in $logicalDisks | Where-Object DriveType -eq 3) {
    $letter = $disk.DeviceID.Substring(0, 1)
    $matching = @($volumes | Where-Object { [string]$_.DriveLetter -eq $letter })
    if ($matching.Count -ne 1 -or $matching[0].FileSystem -ne $disk.FileSystem) {
        throw "Get-Volume and Win32_LogicalDisk disagree for $($disk.DeviceID)"
    }
    $volumeInfo = @($fsutil | Where-Object Command -eq "fsutil.exe fsinfo volumeinfo $($disk.DeviceID)")
    $filesystemPattern = '(?m)^File System Name\s*:\s*' + [regex]::Escape($disk.FileSystem) + '\s*$'
    if ($volumeInfo.Count -ne 1 -or $volumeInfo[0].ExitCode -ne 0 -or
        $volumeInfo[0].Output -notmatch $filesystemPattern) {
        throw "fsutil did not confirm the filesystem for $($disk.DeviceID)"
    }
}
$expectedArchitecture = if ($env:PROBE_IMAGE -like '*-arm') { 'Arm64' } else { 'X64' }
if ($report.OSArchitecture -ne $expectedArchitecture) {
    throw "Expected $expectedArchitecture but observed $($report.OSArchitecture)"
}
# Actions otherwise propagates the last diagnostic fsutil exit code on Server 2022.
exit 0
