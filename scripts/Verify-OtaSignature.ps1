#requires -Version 7.0
<#
Read-only Android whole-file OTA signature verification for the exact signature
format used by this case: one RSA signer, SHA-1, and no signed attributes.
The trusted public certificate is pinned to the one compared with the phone.
This script does not contact a device, modify a ZIP, or validate other models.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FirmwarePath,
    [string]$TrustedCertificatePath = (Join-Path $PSScriptRoot '../data/oneplus-ota-certificate.pem')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security.Cryptography.Pkcs

function Read-Exactly {
    param([System.IO.Stream]$Stream, [byte[]]$Buffer)
    $offset = 0
    while ($offset -lt $Buffer.Length) {
        $count = $Stream.Read($Buffer, $offset, $Buffer.Length - $offset)
        if ($count -le 0) { throw 'Unexpected end of file.' }
        $offset += $count
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../data/artifacts.json') -Raw | ConvertFrom-Json
$expected = $manifest.artifacts | Where-Object id -eq 'oxygenos_rollback'
$file = Get-Item -LiteralPath $FirmwarePath
if ($file.PSIsContainer) { throw 'FirmwarePath must be a file.' }
if ($file.Length -ne $expected.size_bytes) { throw 'Unexpected size for the case firmware.' }

$trustedPath = (Resolve-Path -LiteralPath $TrustedCertificatePath).Path
$pemText = [System.IO.File]::ReadAllText($trustedPath)
$pemMatch = [regex]::Match($pemText, '(?s)-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----')
if (-not $pemMatch.Success) { throw 'Trusted certificate must be a PEM certificate.' }
$certificateDer = [Convert]::FromBase64String($pemMatch.Groups[1].Value)
$trusted = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateDer)
$rsa = $null
$digest = $null
$stream = $null
try {
    $trustedSha256 = $trusted.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256)
    if ($trustedSha256 -cne $expected.ota_certificate_sha256) { throw 'Trusted certificate does not match the case record.' }
    $stream = [System.IO.File]::OpenRead($file.FullName)
    if ($stream.Length -lt 28) { throw 'File is too short for an OTA signature.' }

    $footer = [byte[]]::new(6)
    [void]$stream.Seek(-6, [System.IO.SeekOrigin]::End)
    Read-Exactly $stream $footer
    if ($footer[2] -ne 255 -or $footer[3] -ne 255) { throw 'Android OTA signature footer is missing.' }
    $signatureStart = [int]$footer[0] + 256 * [int]$footer[1]
    $commentSize = [int]$footer[4] + 256 * [int]$footer[5]
    if ($signatureStart -le 6 -or $signatureStart -gt $commentSize) { throw 'Invalid signature/comment length.' }

    $eocd = [byte[]]::new(22 + $commentSize)
    [void]$stream.Seek(-$eocd.Length, [System.IO.SeekOrigin]::End)
    Read-Exactly $stream $eocd
    if ($eocd[0] -ne 0x50 -or $eocd[1] -ne 0x4b -or $eocd[2] -ne 0x05 -or $eocd[3] -ne 0x06) {
        throw 'ZIP end-of-central-directory record is invalid.'
    }
    if (([int]$eocd[20] + 256 * [int]$eocd[21]) -ne $commentSize) { throw 'ZIP comment length disagrees with the signature footer.' }
    for ($i = 4; $i -le $eocd.Length - 4; $i++) {
        if ($eocd[$i] -eq 0x50 -and $eocd[$i + 1] -eq 0x4b -and $eocd[$i + 2] -eq 0x05 -and $eocd[$i + 3] -eq 0x06) {
            throw 'Ambiguous additional ZIP end marker in signature area.'
        }
    }

    $pkcs7 = [byte[]]::new($signatureStart - 6)
    [Array]::Copy($eocd, $eocd.Length - $signatureStart, $pkcs7, 0, $pkcs7.Length)
    $cms = [System.Security.Cryptography.Pkcs.SignedCms]::new()
    $cms.Decode($pkcs7)
    if ($cms.SignerInfos.Count -ne 1) { throw 'Expected exactly one OTA signer.' }
    $signer = $cms.SignerInfos[0]
    if ($null -eq $signer.Certificate) { throw 'Signer certificate is missing.' }
    $signerSha256 = $signer.Certificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256)
    if ($signerSha256 -cne $trustedSha256) { throw 'OTA signer does not match the pinned trusted certificate.' }
    if ($signer.SignedAttributes.Count -ne 0) { throw 'Signed attributes are outside this case-specific verifier format.' }
    if ($signer.DigestAlgorithm.Value -ne '1.3.14.3.2.26') { throw 'Unexpected digest algorithm; this case uses SHA-1.' }

    [long]$signedLength = $stream.Length - $commentSize - 2
    if ($signedLength -le 0) { throw 'Invalid signed length.' }
    $digest = [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA1)
    [void]$stream.Seek(0, [System.IO.SeekOrigin]::Begin)
    $buffer = [byte[]]::new(1024 * 1024)
    [long]$remaining = $signedLength
    while ($remaining -gt 0) {
        $requested = [int][Math]::Min([long]$buffer.Length, $remaining)
        $count = $stream.Read($buffer, 0, $requested)
        if ($count -le 0) { throw 'Unexpected end inside the signed file range.' }
        $digest.AppendData($buffer, 0, $count)
        $remaining -= $count
    }
    $hash = $digest.GetHashAndReset()
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($trusted)
    if ($null -eq $rsa) { throw 'Trusted certificate must contain an RSA public key.' }
    $verified = $rsa.VerifyHash($hash, $signer.GetSignature(), [System.Security.Cryptography.HashAlgorithmName]::SHA1, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    if (-not $verified) { throw 'Full OTA RSA signature verification failed.' }

    [pscustomobject]@{
        SchemaVersion = 1
        SignatureVerified = $true
        SignerMatchesPinnedCaseCertificate = $true
        CertificateSHA256 = $trustedSha256
        SignedLength = $signedLength
        SignatureStart = $signatureStart
        CommentSize = $commentSize
        DigestAlgorithm = $signer.DigestAlgorithm.Value
        SignedAttributeCount = $signer.SignedAttributes.Count
        Scope = 'Android whole-file OTA signature for the pinned case certificate; not a device compatibility or unlock check.'
    } | ConvertTo-Json -Depth 4
} finally {
    if ($null -ne $rsa) { $rsa.Dispose() }
    if ($null -ne $digest) { $digest.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
    $trusted.Dispose()
}
