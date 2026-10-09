param(
    [Parameter(Mandatory = $true)][string]$Origin,
    [string]$Certificate = 'deployment/tls/server.pem',
    [string]$PrivateKey = 'deployment/tls/server-key.pem',
    [switch]$PrebuiltWeb
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$uri = [Uri]$Origin
if ($uri.Scheme -ne 'https' -or $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or $uri.UserInfo) {
    throw 'Origin must be one HTTPS origin without path, credentials, query or fragment.'
}
$Origin = $uri.GetLeftPart([UriPartial]::Authority)
if (!(Test-Path $Certificate -PathType Leaf) -or !(Test-Path $PrivateKey -PathType Leaf)) {
    throw 'Create TLS certificate/key with mkcert first. No automatic certificate service is contacted.'
}
if (!(Test-Path '.env')) {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $dbBytes = New-Object byte[] 32
        $jwtBytes = New-Object byte[] 48
        $rng.GetBytes($dbBytes)
        $rng.GetBytes($jwtBytes)
        $dbSecret = ([BitConverter]::ToString($dbBytes)).Replace('-', '').ToLowerInvariant()
        $jwtSecret = ([BitConverter]::ToString($jwtBytes)).Replace('-', '').ToLowerInvariant()
        $contents = [IO.File]::ReadAllText((Join-Path (Get-Location) '.env.example'))
        $contents = $contents -replace '(?m)^POSTGRES_PASSWORD=.*$', "POSTGRES_PASSWORD=$dbSecret"
        $contents = $contents -replace '(?m)^JWT_SECRET=.*$', "JWT_SECRET=$jwtSecret"
        $contents = $contents -replace '(?m)^PUBLIC_APP_URL=.*$', "PUBLIC_APP_URL=$Origin"
        $contents = $contents -replace '(?m)^CORS_ORIGINS=.*$', "CORS_ORIGINS=$Origin"
        $contents = $contents -replace '(?m)^HTTPS_PORT=.*$', "HTTPS_PORT=$($uri.Port)"
        $certPath = (Resolve-Path $Certificate).Path.Replace('\', '/')
        $keyPath = (Resolve-Path $PrivateKey).Path.Replace('\', '/')
        $contents = $contents -replace '(?m)^TLS_CERT_PATH=.*$', "TLS_CERT_PATH=$certPath"
        $contents = $contents -replace '(?m)^TLS_KEY_PATH=.*$', "TLS_KEY_PATH=$keyPath"
        [IO.File]::WriteAllText((Join-Path (Get-Location) '.env'), $contents, (New-Object Text.UTF8Encoding $false))
    } finally {
        $rng.Dispose()
        $dbSecret = $null
        $jwtSecret = $null
    }
    Write-Host 'Created local .env with random secrets. Restrict this file to your Windows account.'
} else {
    Write-Host '.env exists and is preserved; Origin/certificate changes require a deliberate .env edit.'
}
& node scripts/prepare-db-role-env.mjs --write
if ($LASTEXITCODE -ne 0) { throw 'Independent database role environment preparation failed.' }
if ((Get-Content '.env' -Raw) -match '(?m)^(POSTGRES_PASSWORD|API_DB_PASSWORD|MIGRATOR_DB_PASSWORD|BACKUP_DB_PASSWORD|JWT_SECRET)=CHANGE_ME') {
    throw 'Replace placeholder secrets in .env.'
}
$endpoint = $null
$dockerContextExit = 0
if ($env:DOCKER_CONTEXT) {
    $endpoint = docker context inspect $env:DOCKER_CONTEXT --format '{{.Endpoints.docker.Host}}'
    $dockerContextExit = $LASTEXITCODE
} elseif ($env:DOCKER_HOST) {
    $endpoint = $env:DOCKER_HOST
} else {
    $endpoint = docker context inspect --format '{{.Endpoints.docker.Host}}'
    $dockerContextExit = $LASTEXITCODE
}
if ($dockerContextExit -ne 0 -or $endpoint -notmatch '^(unix|npipe)://') {
    throw 'Refusing a remote Docker endpoint; use local Docker Desktop.'
}
function Invoke-CheckedDocker {
    param([string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed with exit code $LASTEXITCODE" }
}
Invoke-CheckedDocker -Arguments @('info', '--format', '{{.ServerVersion}}')
Invoke-CheckedDocker -Arguments @('compose', 'config', '--quiet')
$composeBuild = @('compose', '-f', 'docker-compose.yml')
if ($PrebuiltWeb) {
    & node scripts/prebuilt-web-check.mjs apps/lifemate
    if ($LASTEXITCODE -ne 0) { throw 'Prebuilt web artifact is missing, stale or has external resources.' }
    $composeBuild += @('-f', 'docker-compose.prebuilt-web.yml')
}
if ($env:BUILD_CA_FILE) {
    if (!(Test-Path $env:BUILD_CA_FILE -PathType Leaf) -or ((Get-Content $env:BUILD_CA_FILE -Raw) -match 'PRIVATE KEY')) {
        throw 'BUILD_CA_FILE must contain a public CA certificate, never a private key.'
    }
    Invoke-CheckedDocker -Arguments ($composeBuild + @('-f', 'docker-compose.build-proxy.yml', 'build', 'api', 'gateway', 'backup'))
} else {
    Invoke-CheckedDocker -Arguments ($composeBuild + @('build', '--build-arg', 'HTTP_PROXY', '--build-arg', 'HTTPS_PROXY', 'api', 'gateway', 'backup'))
}
Invoke-CheckedDocker -Arguments @('compose', 'up', '-d', '--wait', '--wait-timeout', '120', 'postgres')
Invoke-CheckedDocker -Arguments @('compose', 'run', '--rm', '--no-deps', 'db-provision')
Invoke-CheckedDocker -Arguments @('compose', 'run', '--rm', '--no-deps', 'migrate')
Invoke-CheckedDocker -Arguments @('compose', 'run', '--rm', '--no-deps', 'db-grants')
Invoke-CheckedDocker -Arguments @('compose', 'up', '-d', '--wait', '--wait-timeout', '180', 'api', 'gateway', 'backup')
Invoke-CheckedDocker -Arguments @('compose', 'ps')
Write-Host 'Local stack started. Run the HTTPS smoke test with synthetic accounts.'
