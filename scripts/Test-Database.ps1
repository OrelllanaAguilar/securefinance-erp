[CmdletBinding()]
param(
    [string]$EnvironmentPath = ''
)

$ErrorActionPreference = 'Stop'
$rootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($EnvironmentPath)) {
    $EnvironmentPath = Join-Path $rootPath '.env'
}
$EnvironmentPath = [System.IO.Path]::GetFullPath($EnvironmentPath)
if (-not (Test-Path -LiteralPath $EnvironmentPath)) { throw "No existe $EnvironmentPath" }
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { throw 'No se encontro sqlcmd.' }

$values = @{}
foreach ($line in [IO.File]::ReadAllLines($EnvironmentPath)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    $separator = $line.IndexOf('=')
    if ($separator -lt 1) { continue }
    $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
}
foreach ($required in @('DB_SERVER', 'DB_NAME', 'DB_USER', 'DB_PASSWORD')) {
    if (-not $values.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($values[$required])) {
        throw "Falta $required en $EnvironmentPath"
    }
}

$server = $values.DB_SERVER
if (-not [string]::IsNullOrWhiteSpace($values.DB_PORT)) {
    $server = "$server,$($values.DB_PORT)"
}
elseif (-not [string]::IsNullOrWhiteSpace($values.DB_INSTANCE)) {
    $server = "$server\$($values.DB_INSTANCE)"
}

$previousPassword = $env:SQLCMDPASSWORD
try {
    $env:SQLCMDPASSWORD = $values.DB_PASSWORD
    & sqlcmd -S $server -U $values.DB_USER -d $values.DB_NAME -C -b -r 1 -Q "SET NOCOUNT ON; EXEC dbo.sp_VerificarEstado;"
    if ($LASTEXITCODE -ne 0) { throw "La verificacion termino con codigo $LASTEXITCODE." }
}
finally {
    $env:SQLCMDPASSWORD = $previousPassword
}
