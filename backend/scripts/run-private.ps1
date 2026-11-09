param(
    [Parameter(Mandatory)][ValidateSet('snapshot','auth','import','files')][string]$Task,
    [string]$Snapshot
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$private = (New-Item -ItemType Directory -Path .private -Force).FullName
$keyPath = Join-Path $private 'archive-key.dpapi'
if (-not (Test-Path -LiteralPath $keyPath)) {
    if ($Task -ne 'snapshot' -or (Test-Path -LiteralPath (Join-Path $private 'snapshots'))) {
        throw 'Existing backup key is missing. Restore it before continuing.'
    }
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $hex = [BitConverter]::ToString($bytes).Replace('-', '')
    $encrypted = ConvertTo-SecureString $hex -AsPlainText -Force | ConvertFrom-SecureString
    [IO.File]::WriteAllText($keyPath, $encrypted)
}

function Read-LocalSecret([string]$Name) {
    $secure = Get-Content -LiteralPath (Join-Path $private $Name) | ConvertTo-SecureString
    [Net.NetworkCredential]::new('', $secure).Password
}

try {
    $env:EFATA_ARCHIVE_KEY = Read-LocalSecret 'archive-key.dpapi'
    if ($Task -in 'snapshot','auth') {
        $gcloud = Get-Command gcloud.cmd -ErrorAction SilentlyContinue
        if ($gcloud) { $cli = $gcloud.Source } else { $cli = $env:EFATA_GCLOUD_PATH }
        if (-not $cli) { throw 'Set EFATA_GCLOUD_PATH to your gcloud.cmd path.' }
        $env:EFATA_GOOGLE_ACCESS_TOKEN = (& $cli auth print-access-token --quiet).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $env:EFATA_GOOGLE_ACCESS_TOKEN) { throw 'Google CLI auth failed.' }
        if ($Task -eq 'snapshot') {
            node scripts/snapshot.mjs
        } else {
            node scripts/recover-auth.mjs $Snapshot
        }
    } elseif ($Task -eq 'import') {
        $env:EFATA_DB_PASSWORD = Read-LocalSecret 'supabase-db.dpapi'
        $env:EFATA_DB_POOLER_URL = (Get-Content -LiteralPath 'supabase/.temp/pooler-url' -Raw).Trim()
        $ca = Join-Path $private 'supabase-ca.crt'
        if (-not $env:NODE_EXTRA_CA_CERTS -and (Test-Path -LiteralPath $ca)) {
            $env:NODE_EXTRA_CA_CERTS = $ca
        }
        node scripts/import.mjs $Snapshot
    } else {
        node scripts/upload-files.mjs $Snapshot
    }
    exit $LASTEXITCODE
} finally {
    Remove-Item Env:EFATA_ARCHIVE_KEY,Env:EFATA_GOOGLE_ACCESS_TOKEN,Env:EFATA_DB_PASSWORD,Env:EFATA_DB_POOLER_URL -ErrorAction SilentlyContinue
}
