#requires -Version 7.0
<#
Build the archival assets locally from the files used in the documented case.
Does not upload anything or interact with a phone. OutputDirectory must be new.
The firmware is split as raw bytes, without modifying its ZIP or OTA signature.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FirmwarePath,
    [Parameter(Mandatory)][string]$UpdaterApkPath,
    [Parameter(Mandatory)][string]$PlatformToolsDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Verify-Artifacts.ps1') -FirmwarePath $FirmwarePath -UpdaterApkPath $UpdaterApkPath | Out-Null
$caseManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../data/artifacts.json') -Raw | ConvertFrom-Json
$firmwareRecord = $caseManifest.artifacts | Where-Object id -eq 'oxygenos_rollback'
$apkRecord = $caseManifest.artifacts | Where-Object id -eq 'local_updater_apk'
$toolsRoot = (Resolve-Path -LiteralPath $PlatformToolsDirectory).Path
$properties = Get-Content -LiteralPath (Join-Path $toolsRoot 'source.properties') -Raw
if ($properties -notmatch '(?m)^Pkg\.Revision=37\.0\.1\s*$') { throw 'Expected Platform Tools 37.0.1.' }
$toolsNames = @('adb.exe', 'fastboot.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll', 'libwinpthread-1.dll', 'NOTICE.txt', 'source.properties')
foreach ($name in $toolsNames) { if (-not (Test-Path -LiteralPath (Join-Path $toolsRoot $name) -PathType Leaf)) { throw "Missing required tool member: $name" } }

$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw 'OutputDirectory already exists; existing archives are never overwritten.' }
[void][System.IO.Directory]::CreateDirectory($outputRoot)
$releaseTag = 'assets-2026-09-16'
$releaseBase = 'https://github.com/ACGHINQU/oneplus7-coloros-to-oxygenos/releases/download/' + $releaseTag + '/'
[long]$partSize = 1610612736
$partRecords = [System.Collections.Generic.List[object]]::new()
$sourceStream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $FirmwarePath).Path)
try {
    $buffer = [byte[]]::new(4 * 1024 * 1024)
    $index = 1
    while ($sourceStream.Position -lt $sourceStream.Length) {
        $partName = $firmwareRecord.file_name + ('.part{0:d3}' -f $index)
        $partPath = Join-Path $outputRoot $partName
        $partStream = [System.IO.File]::Open($partPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        $partHash = [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
        [long]$written = 0
        try {
            while ($written -lt $partSize -and $sourceStream.Position -lt $sourceStream.Length) {
                $requested = [int][Math]::Min([long]$buffer.Length, $partSize - $written)
                $count = $sourceStream.Read($buffer, 0, $requested)
                if ($count -le 0) { throw 'Unexpected end of firmware.' }
                $partStream.Write($buffer, 0, $count)
                $partHash.AppendData($buffer, 0, $count)
                $written += $count
            }
            $partRecords.Add([ordered]@{ file_name = $partName; size_bytes = $written; sha256 = [BitConverter]::ToString($partHash.GetHashAndReset()).Replace('-', ''); download_url = $releaseBase + $partName })
        } finally { $partStream.Dispose(); $partHash.Dispose() }
        $index++
    }
} finally { $sourceStream.Dispose() }

$apkName = 'OPLocalUpdate_For_Android12.apk'
Copy-Item -LiteralPath $UpdaterApkPath -Destination (Join-Path $outputRoot $apkName)
$toolsName = 'adb-fastboot-windows-37.0.1-case-tools.zip'
$toolsZipPath = Join-Path $outputRoot $toolsName
$toolsMembers = [System.Collections.Generic.List[object]]::new()
$zip = [System.IO.Compression.ZipFile]::Open($toolsZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in $toolsNames) {
        $memberPath = Join-Path $toolsRoot $name
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $memberPath, ('platform-tools/' + $name), [System.IO.Compression.CompressionLevel]::Optimal)
        $toolsMembers.Add([ordered]@{ path = 'platform-tools/' + $name; size_bytes = (Get-Item -LiteralPath $memberPath).Length; sha256 = (Get-FileHash -LiteralPath $memberPath -Algorithm SHA256).Hash })
    }
} finally { $zip.Dispose() }

$archive = [ordered]@{
    schema_version = 1
    archived_date = '2026-09-16'
    release_tag = $releaseTag
    release_url = 'https://github.com/ACGHINQU/oneplus7-coloros-to-oxygenos/releases/tag/' + $releaseTag
    firmware = [ordered]@{ file_name = $firmwareRecord.file_name; size_bytes = $firmwareRecord.size_bytes; sha256 = $firmwareRecord.sha256; split_method = 'ordered raw byte ranges; no ZIP modification or recompression'; parts = @($partRecords.ToArray()) }
    assets = @(
        [ordered]@{ id = 'local_updater_apk'; file_name = $apkName; size_bytes = $apkRecord.size_bytes; sha256 = $apkRecord.sha256; download_url = $releaseBase + $apkName },
        [ordered]@{ id = 'adb_fastboot_subset'; file_name = $toolsName; size_bytes = (Get-Item -LiteralPath $toolsZipPath).Length; sha256 = (Get-FileHash -LiteralPath $toolsZipPath -Algorithm SHA256).Hash; download_url = $releaseBase + $toolsName; packaging = 'Case-specific subset assembled from original Platform Tools 37.0.1. Binaries are unchanged; original NOTICE.txt retained. Not the complete Google SDK archive.'; members = @($toolsMembers.ToArray()) }
    )
}
$archive | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputRoot 'archive-manifest.json') -Encoding utf8NoBOM
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Restore-Firmware.ps1') -Destination (Join-Path $outputRoot 'Restore-Firmware.ps1')
[pscustomobject]@{ FirmwareParts = $partRecords.Count; FirmwareBytes = $firmwareRecord.size_bytes; ToolsMembers = $toolsMembers.Count; ManifestName = 'archive-manifest.json' } | ConvertTo-Json
