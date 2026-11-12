param(
    [ValidateSet('health','api','all')][string]$Role = 'all'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$projectRef = 'fwjxmutbsiokeevgvbat'
$privateRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ownerSecretPath = Join-Path $privateRoot 'supabase-db.dpapi'
$caPath = Join-Path $privateRoot 'supabase-ca.crt'
$poolerUrl = "postgresql://postgres.$projectRef@aws-0-eu-west-2.pooler.supabase.com:6543/postgres"

function Read-DpapiSecret([string]$Path) {
    $secure = Get-Content -LiteralPath $Path | ConvertTo-SecureString
    [Net.NetworkCredential]::new('', $secure).Password
}

function New-Password {
    $bytes = New-Object byte[] 36
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    [Convert]::ToBase64String($bytes).Replace('+', 'A').Replace('/', 'b')
}

function Protect-Secret([string]$Path, [string]$Value) {
    $encrypted = ConvertTo-SecureString $Value -AsPlainText -Force | ConvertFrom-SecureString
    [IO.File]::WriteAllText($Path, $encrypted)
}

if (-not (Test-Path -LiteralPath $ownerSecretPath)) {
    throw 'The protected EFATA Supabase owner password is missing.'
}
$ownerPassword = Read-DpapiSecret $ownerSecretPath
$pooler = [UriBuilder]::new($poolerUrl)
if ($pooler.UserName -ne "postgres.$projectRef" -or -not $pooler.Host.EndsWith('.pooler.supabase.com')) {
    throw 'Refusing to provision roles on an unexpected database.'
}

$roles = if ($Role -eq 'all') { @('health', 'api') } else { @($Role) }
$specs = @{
    health = @{ DatabaseRole = 'efata_health_reader'; SecretFile = 'health-reader.dpapi' }
    api = @{ DatabaseRole = 'efata_api_runtime'; SecretFile = 'api-runtime.dpapi' }
}

$env:EFATA_DB_POOLER_URL = $pooler.Uri.AbsoluteUri
$env:EFATA_DB_PASSWORD = $ownerPassword
if (Test-Path -LiteralPath $caPath) { $env:NODE_EXTRA_CA_CERTS = $caPath }
try {
    foreach ($name in $roles) {
        $spec = $specs[$name]
        $password = New-Password
        $secretPath = Join-Path $privateRoot $spec.SecretFile
        Protect-Secret $secretPath $password
        $env:EFATA_RUNTIME_ROLE = $spec.DatabaseRole
        $env:EFATA_RUNTIME_PASSWORD = $password
        node scripts/set-role-password.mjs
        if ($LASTEXITCODE -ne 0) { throw "Failed to provision $($spec.DatabaseRole)." }
    }
} finally {
    Remove-Item Env:EFATA_DB_POOLER_URL,Env:EFATA_DB_PASSWORD,Env:EFATA_RUNTIME_ROLE,Env:EFATA_RUNTIME_PASSWORD,Env:NODE_EXTRA_CA_CERTS -ErrorAction SilentlyContinue
}

Write-Host 'EFATA runtime database roles were provisioned. Passwords remain DPAPI-protected locally.'

