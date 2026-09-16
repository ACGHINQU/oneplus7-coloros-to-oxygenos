#requires -Version 7.0
<#
Reassemble the archived firmware as an exact byte-for-byte copy of the original.
Reads local files only. Never contacts or flashes a phone. Existing output files
are verified and reused; an existing file with a different hash is not replaced.
#>
[CmdletBinding()]
param(
    [string]$PartsDirectory = $PSScriptRoot,
    [string]$OutputDirectory,
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$expectedName = 'OnePlus7Oxygen_14.P.41_OTA_0410_all_2112101753_downgrade_da90e698650240ff.zip'
$expectedSize = 2579323479L
$expectedHash = 'E15EE75F64CF6E19AE7696A0C933C5AA3B811850A0BC67407CB2D669DC74C19E'
$partsRoot = (Resolve-Path -LiteralPath $PartsDirectory).Path
if (-not (Test-Path -LiteralPath $partsRoot -PathType Container)) { throw 'PartsDirectory must be a directory.' }
if (-not $ManifestPath) { $ManifestPath = Join-Path $partsRoot 'archive-manifest.json' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1) { throw 'Unsupported archive manifest version.' }
if ($manifest.firmware.file_name -cne $expectedName -or
    $manifest.firmware.size_bytes -ne $expectedSize -or
    $manifest.firmware.sha256 -cne $expectedHash) { throw 'Manifest does not describe the verified case firmware.' }

if (-not $OutputDirectory) { $OutputDirectory = $partsRoot }
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
[void][System.IO.Directory]::CreateDirectory($outputRoot)
$outputPath = Join-Path $outputRoot $expectedName
if (Test-Path -LiteralPath $outputPath) {
    $existing = Get-Item -LiteralPath $outputPath
    if ($existing.PSIsContainer -or $existing.Length -ne $expectedSize -or
        (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash -cne $expectedHash) {
        throw 'An output with different contents already exists; it was not changed.'
    }
    [pscustomobject]@{ FileName = $expectedName; SHA256 = $expectedHash; SizeBytes = $expectedSize; RestoredExactly = $true; AlreadyPresent = $true } | ConvertTo-Json
    return
}

$parts = @($manifest.firmware.parts)
if ($parts.Count -lt 1) { throw 'No firmware parts in manifest.' }
$seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
[long]$total = 0
$partPaths = foreach ($part in $parts) {
    if ([string]::IsNullOrWhiteSpace($part.file_name) -or
        [System.IO.Path]::GetFileName($part.file_name) -cne $part.file_name -or
        $part.file_name -match '[\\/:]' -or
        -not $seenNames.Add($part.file_name)) { throw 'Unsafe or duplicate part file name.' }
    if ($part.size_bytes -le 0 -or $part.size_bytes -gt $expectedSize -or $part.sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'Invalid part size or checksum.'
    }
    $partPath = Join-Path $partsRoot $part.file_name
    $partFile = Get-Item -LiteralPath $partPath
    if ($partFile.PSIsContainer -or $partFile.Length -ne $part.size_bytes) { throw "Part size mismatch: $($part.file_name)" }
    if ((Get-FileHash -LiteralPath $partPath -Algorithm SHA256).Hash -ine $part.sha256) { throw "Part SHA256 mismatch: $($part.file_name)" }
    $total += $partFile.Length
    $partFile.FullName
}
if ($total -ne $expectedSize) { throw 'Combined part length does not match the original firmware.' }

$temporaryPath = $outputPath + '.partial'
$outputStream = $null
$wholeHash = $null
$createdTemporary = $false
try {
    $outputStream = [System.IO.FileStream]::new($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $createdTemporary = $true
    $wholeHash = [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $buffer = [byte[]]::new(4 * 1024 * 1024)
    foreach ($partPath in $partPaths) {
        $inputStream = [System.IO.File]::OpenRead($partPath)
        try {
            while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outputStream.Write($buffer, 0, $count)
                $wholeHash.AppendData($buffer, 0, $count)
            }
        } finally { $inputStream.Dispose() }
    }
    $actualHash = [BitConverter]::ToString($wholeHash.GetHashAndReset()).Replace('-', '')
    if ($outputStream.Length -ne $expectedSize -or $actualHash -cne $expectedHash) { throw 'Reassembled firmware does not match the original SHA256.' }
    $outputStream.Dispose()
    $outputStream = $null
    [System.IO.File]::Move($temporaryPath, $outputPath)
    $createdTemporary = $false
    [pscustomobject]@{ FileName = $expectedName; SHA256 = $actualHash; SizeBytes = $expectedSize; RestoredExactly = $true; AlreadyPresent = $false } | ConvertTo-Json
} finally {
    if ($null -ne $outputStream) { $outputStream.Dispose() }
    if ($null -ne $wholeHash) { $wholeHash.Dispose() }
    if ($createdTemporary -and [System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
}
