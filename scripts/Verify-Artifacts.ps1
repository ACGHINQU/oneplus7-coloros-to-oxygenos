#requires -Version 7.0
<#
Read-only file identity checks for the two artifacts used in this case.
No downloads, ADB commands, fastboot commands, or device writes are performed.
#>
[CmdletBinding()]
param(
    [string]$FirmwarePath,
    [string]$UpdaterApkPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot '../data/artifacts.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$requests = @()
if ($FirmwarePath) { $requests += @{ Id = 'oxygenos_rollback'; Path = $FirmwarePath } }
if ($UpdaterApkPath) { $requests += @{ Id = 'local_updater_apk'; Path = $UpdaterApkPath } }
if ($requests.Count -eq 0) { throw 'Supply -FirmwarePath, -UpdaterApkPath, or both.' }

$results = foreach ($request in $requests) {
    $expected = @($manifest.artifacts | Where-Object id -eq $request.Id)
    if ($expected.Count -ne 1) { throw "Manifest must contain exactly one artifact: $($request.Id)" }
    $expected = $expected[0]
    $file = Get-Item -LiteralPath $request.Path
    if ($file.PSIsContainer) { throw "Expected a file for $($request.Id)." }
    if ($file.Length -ne $expected.size_bytes) {
        throw "Size mismatch for $($request.Id): expected $($expected.size_bytes), got $($file.Length)."
    }
    $actual = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if ($actual -cne $expected.sha256) { throw "SHA256 mismatch for $($request.Id)." }
    [pscustomobject]@{
        Artifact = $request.Id
        ExpectedFileName = $expected.file_name
        SizeBytes = $file.Length
        SHA256 = $actual
        IdentityMatchesCaseArtifact = $true
        CheckScope = 'Size and SHA256 only; this result is not a cryptographic signature verification.'
    }
}

[pscustomobject]@{ SchemaVersion = 1; Results = @($results) } | ConvertTo-Json -Depth 5
