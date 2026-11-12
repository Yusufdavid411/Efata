$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$projectRef = 'fwjxmutbsiokeevgvbat'
$privateRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$caPath = Join-Path $privateRoot 'supabase-ca.crt'

function Read-DpapiSecret([string]$Name) {
    $secure = Get-Content -LiteralPath (Join-Path $privateRoot $Name) | ConvertTo-SecureString
    [Net.NetworkCredential]::new('', $secure).Password
}

$env:NODE_EXTRA_CA_CERTS = $caPath
$env:EFATA_POOLER_HOST = 'aws-0-eu-west-2.pooler.supabase.com'
$env:EFATA_PROJECT_REF = $projectRef
try {
    $env:EFATA_TEST_ROLE = 'efata_health_reader'
    $env:EFATA_TEST_PASSWORD = Read-DpapiSecret 'health-reader.dpapi'
    $env:EFATA_EXPECT_TABLE_ACCESS = '0'
    node scripts/verify-role-access.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Health role verification failed.' }

    $env:EFATA_TEST_ROLE = 'efata_api_runtime'
    $env:EFATA_TEST_PASSWORD = Read-DpapiSecret 'api-runtime.dpapi'
    $env:EFATA_EXPECT_TABLE_ACCESS = '1'
    node scripts/verify-role-access.mjs
    if ($LASTEXITCODE -ne 0) { throw 'API role verification failed.' }
} finally {
    Remove-Item Env:NODE_EXTRA_CA_CERTS,Env:EFATA_POOLER_HOST,Env:EFATA_PROJECT_REF,Env:EFATA_TEST_ROLE,Env:EFATA_TEST_PASSWORD,Env:EFATA_EXPECT_TABLE_ACCESS -ErrorAction SilentlyContinue
}

Write-Host 'EFATA health and API database role boundaries are correct.'

