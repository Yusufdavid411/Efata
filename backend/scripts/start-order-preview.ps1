param(
    [Parameter(Mandatory)][string]$SnapshotId
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

if ($SnapshotId -notmatch '^\d{4}-\d{2}-\d{2}T[\d-]+Z$') {
    throw 'Provide a verified snapshot directory name.'
}
if (-not $env:EFATA_FIREBASE_LOOKUP_API_KEY) {
    throw 'Set EFATA_FIREBASE_LOOKUP_API_KEY before starting the preview.'
}
$connection = [UriBuilder]::new((Get-Content -LiteralPath 'supabase/.temp/pooler-url' -Raw).Trim())
if ($connection.UserName -ne 'postgres.fwjxmutbsiokeevgvbat' -or
    -not $connection.Host.EndsWith('.pooler.supabase.com') -or
    $connection.Query -or $connection.Fragment) {
    throw 'Refusing to connect to an unexpected Supabase project.'
}
$secret = Get-Content -LiteralPath '.private/preview-reader.dpapi' | ConvertTo-SecureString
$connection.UserName = 'efata_preview_reader.fwjxmutbsiokeevgvbat'
$connection.Password = [Net.NetworkCredential]::new('', $secret).Password

$env:EFATA_PREVIEW_DATABASE_URL = $connection.Uri.AbsoluteUri
$env:EFATA_PREVIEW_SNAPSHOT_ID = $SnapshotId
$env:EFATA_ORDER_PREVIEW = '1'
$env:EFATA_DB_CA_PEM = Get-Content -LiteralPath '.private/supabase-ca.crt' -Raw
if (-not $env:EFATA_PREVIEW_ORIGINS) {
    $env:EFATA_PREVIEW_ORIGINS = 'http://127.0.0.1:5173,http://localhost:5173'
}
try {
    node scripts/serve.mjs
    exit $LASTEXITCODE
} finally {
    Remove-Item Env:EFATA_PREVIEW_DATABASE_URL,Env:EFATA_PREVIEW_SNAPSHOT_ID,Env:EFATA_ORDER_PREVIEW,Env:EFATA_DB_CA_PEM -ErrorAction SilentlyContinue
}
