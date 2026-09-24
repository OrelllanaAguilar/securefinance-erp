[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,63}$')]
    [string]$DatabaseName = 'SecureFinanceERP',

    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,63}$')]
    [string]$ApiLoginName = 'SecureFinanceApi',

    [ValidatePattern('^[A-Za-z0-9._-]{3,50}$')]
    [string]$BootstrapUsername = 'admin.local',

    [ValidateLength(2, 120)]
    [string]$BootstrapDisplayName = 'Administrador local',

    [string]$AdminServerInstance = '.\SQLEXPRESS',
    [ValidateSet('127.0.0.1', 'localhost')]
    [string]$ApplicationServer = '127.0.0.1',
    [ValidateRange(1, 65535)]
    [int]$ApplicationPort = 1433,
    [SecureString]$ApiSqlPassword,
    [SecureString]$BootstrapPassword,
    [switch]$IncludeDemoData,
    [switch]$AllowExisting,
    [switch]$SkipEnvironmentFile
)

$ErrorActionPreference = 'Stop'
$rootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installScript = Join-Path $rootPath 'database\install.sql'
$apiProvisionScript = Join-Path $rootPath 'database\provision-api-login.sql'
$bootstrapProvisionScript = Join-Path $rootPath 'database\provision-bootstrap-admin.sql'
$demoScript = Join-Path $rootPath 'database\seed-demo.sql'
$environmentPath = Join-Path $rootPath '.env'
$credentialDirectory = Join-Path $rootPath 'secrets'
$credentialPath = Join-Path $credentialDirectory 'first-access.txt'
$mailboxDirectory = Join-Path $rootPath 'private-mailbox'

function ConvertFrom-PrivateSecureString {
    param([SecureString]$Value)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function New-PrivateRandomText {
    param([int]$ByteCount = 36)
    $bytes = New-Object byte[] $ByteCount
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) }
    finally { $generator.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-PrivatePassword {
    return 'Aa7!' + (New-PrivateRandomText -ByteCount 24).Substring(0, 28)
}

function Protect-PrivateFile {
    param([string]$LiteralPath)
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $item = Get-Item -LiteralPath $LiteralPath
        $acl = if ($item.PSIsContainer) {
            New-Object Security.AccessControl.DirectorySecurity
        }
        else {
            New-Object Security.AccessControl.FileSecurity
        }
        $acl.SetAccessRuleProtection($true, $false)
        $rule = if ($item.PSIsContainer) {
            New-Object Security.AccessControl.FileSystemAccessRule(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow
            )
        }
        else {
            New-Object Security.AccessControl.FileSystemAccessRule(
                $identity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            )
        }
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $LiteralPath -AclObject $acl
    }
    catch {
        Write-Warning "No fue posible restringir ACL de $LiteralPath. Restrinja el archivo manualmente."
    }
}

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'No se encontro sqlcmd. Instale Microsoft sqlcmd antes de preparar SQL Server.'
}
foreach ($requiredScript in @($installScript, $apiProvisionScript, $bootstrapProvisionScript)) {
    if (-not (Test-Path -LiteralPath $requiredScript)) {
        throw "No existe el script SQL requerido: $requiredScript"
    }
}
if ($IncludeDemoData -and $DatabaseName -notmatch '(?i)_test$') {
    throw 'La semilla de demostracion solo se permite en una base cuyo nombre termine en _Test.'
}
if (-not $SkipEnvironmentFile -and (Test-Path -LiteralPath $environmentPath) -and -not $AllowExisting) {
    throw '.env ya existe. Use -AllowExisting para reemplazarlo conscientemente o -SkipEnvironmentFile.'
}
if ($BootstrapDisplayName -match '[''"$]' -or $BootstrapDisplayName.Contains('$(')) {
    throw 'BootstrapDisplayName contiene caracteres no admitidos por el canal SQLCMD.'
}

$apiPasswordPlain = if ($ApiSqlPassword) { ConvertFrom-PrivateSecureString $ApiSqlPassword } else { New-PrivatePassword }
$bootstrapPasswordPlain = if ($BootstrapPassword) { ConvertFrom-PrivateSecureString $BootstrapPassword } else { New-PrivatePassword }
$safeSecretPattern = '^[A-Za-z0-9!#%&*+,\-./:;<=>?@\[\]^_{}~]{16,128}$'
if ($apiPasswordPlain -notmatch $safeSecretPattern) {
    throw 'La contrasena SQL debe tener 16-128 caracteres seguros y no contener comillas, espacios, $, parentesis ni barras invertidas.'
}
if ($bootstrapPasswordPlain -notmatch $safeSecretPattern -or
    $bootstrapPasswordPlain -notmatch '[A-Z]' -or
    $bootstrapPasswordPlain -notmatch '[a-z]' -or
    $bootstrapPasswordPlain -notmatch '[0-9]' -or
    $bootstrapPasswordPlain -notmatch '[^A-Za-z0-9]') {
    throw 'La contrasena inicial debe tener 16-128 caracteres e incluir mayuscula, minuscula, numero y simbolo seguro.'
}

$databaseExistsText = & sqlcmd -S $AdminServerInstance -E -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'$DatabaseName') IS NULL THEN 0 ELSE 1 END;"
if ($LASTEXITCODE -ne 0) { throw 'No fue posible consultar SQL Server con autenticacion integrada.' }
$databaseExists = ($databaseExistsText | Where-Object { $_ -match '^[01]$' } | Select-Object -Last 1) -eq '1'
if ($databaseExists -and -not $AllowExisting) {
    throw "La base $DatabaseName ya existe. El instalador no la modifica sin -AllowExisting."
}
if ($databaseExists -and $null -eq $ApiSqlPassword) {
    throw 'Al usar -AllowExisting debe proporcionar -ApiSqlPassword; no es posible recuperar ni adivinar la clave de un login SQL existente.'
}

$bootstrapAlreadyExists = $false
if ($databaseExists) {
    $bootstrapExistsText = & sqlcmd -S $AdminServerInstance -E -C -b -d $DatabaseName -h -1 -W -Q "SET NOCOUNT ON; IF OBJECT_ID(N'dbo.Usuario',N'U') IS NULL SELECT 0 ELSE SELECT CASE WHEN EXISTS(SELECT 1 FROM dbo.Usuario WHERE NombreUsuario='$BootstrapUsername') THEN 1 ELSE 0 END;"
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible comprobar la cuenta bootstrap existente.' }
    $bootstrapAlreadyExists = ($bootstrapExistsText | Where-Object { $_ -match '^[01]$' } | Select-Object -Last 1) -eq '1'
}
if (-not $bootstrapAlreadyExists -and (Test-Path -LiteralPath $credentialPath)) {
    throw "Ya existe $credentialPath. Conservelo o muevalo antes de generar otra credencial inicial; el instalador no lo sobrescribe."
}

$variableNames = @(
    'DatabaseName', 'ApiLoginName', 'ApiLoginPassword',
    'BootstrapUsername', 'BootstrapDisplayName', 'BootstrapPassword', 'SQLCMDPASSWORD'
)
$previousVariables = @{}
foreach ($name in $variableNames) {
    $previousVariables[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    $env:DatabaseName = $DatabaseName
    $env:ApiLoginName = $ApiLoginName
    $env:ApiLoginPassword = $apiPasswordPlain
    $env:BootstrapUsername = $BootstrapUsername
    $env:BootstrapDisplayName = $BootstrapDisplayName
    $env:BootstrapPassword = $bootstrapPasswordPlain

    Push-Location $rootPath
    try {
        & sqlcmd -S $AdminServerInstance -E -C -b -r 1 -i $installScript
        if ($LASTEXITCODE -ne 0) { throw "La instalacion SQL termino con codigo $LASTEXITCODE." }
        & sqlcmd -S $AdminServerInstance -E -C -b -r 1 -i $apiProvisionScript
        if ($LASTEXITCODE -ne 0) { throw "El aprovisionamiento del login API termino con codigo $LASTEXITCODE." }
        & sqlcmd -S $AdminServerInstance -E -C -b -r 1 -i $bootstrapProvisionScript
        if ($LASTEXITCODE -ne 0) { throw "El aprovisionamiento del primer administrador termino con codigo $LASTEXITCODE." }
        if ($IncludeDemoData) {
            if (-not (Test-Path -LiteralPath $demoScript)) { throw "No existe la semilla demo: $demoScript" }
            & sqlcmd -S $AdminServerInstance -E -C -b -r 1 -i $demoScript
            if ($LASTEXITCODE -ne 0) { throw "La semilla demo termino con codigo $LASTEXITCODE." }
        }

        $env:SQLCMDPASSWORD = $apiPasswordPlain
        $applicationEndpoint = "$ApplicationServer,$ApplicationPort"
        & sqlcmd -S $applicationEndpoint -U $ApiLoginName -d $DatabaseName -C -b -r 1 -Q 'SET NOCOUNT ON; EXEC dbo.sp_VerificarEstado;'
        if ($LASTEXITCODE -ne 0) {
            throw 'El login minimo de la API no pudo conectarse y ejecutar sp_VerificarEstado. Revise TCP, modo mixto y la contrasena proporcionada.'
        }
    }
    finally { Pop-Location }

    if (-not $SkipEnvironmentFile) {
        $csrfSecret = New-PrivateRandomText -ByteCount 48
        $environmentLines = @(
            'HOST=127.0.0.1',
            'PORT=3000',
            'NODE_ENV=development',
            'TRUST_PROXY=false',
            'APP_ORIGIN=http://127.0.0.1:3000',
            'DEV_ORIGIN=http://127.0.0.1:5173',
            'COOKIE_SECURE=false',
            'COOKIE_NAME=sf_session',
            "CSRF_SECRET=$csrfSecret",
            'SESSION_IDLE_MINUTES=30',
            'SESSION_ABSOLUTE_HOURS=8',
            'PASSWORD_RESET_MINUTES=15',
            'CURRENCY_CODE=GTQ',
            'TIME_ZONE=America/Guatemala',
            "DB_SERVER=$ApplicationServer",
            'DB_INSTANCE=',
            "DB_PORT=$ApplicationPort",
            "DB_NAME=$DatabaseName",
            "DB_USER=$ApiLoginName",
            "DB_PASSWORD=$apiPasswordPlain",
            'DB_ENCRYPT=false',
            'DB_TRUST_SERVER_CERTIFICATE=true',
            'DB_POOL_MAX=10',
            'DB_REQUEST_TIMEOUT_MS=15000',
            'RECOVERY_MAILBOX_DIR=./private-mailbox',
            'WEB_DIST_DIR=../web/dist'
        )
        [IO.File]::WriteAllText($environmentPath, ($environmentLines -join [Environment]::NewLine) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        Protect-PrivateFile -LiteralPath $environmentPath
    }

    if (-not (Test-Path -LiteralPath $mailboxDirectory)) {
        New-Item -ItemType Directory -Path $mailboxDirectory | Out-Null
    }
    Protect-PrivateFile -LiteralPath $mailboxDirectory

    if (-not $bootstrapAlreadyExists) {
        if (-not (Test-Path -LiteralPath $credentialDirectory)) {
            New-Item -ItemType Directory -Path $credentialDirectory | Out-Null
        }
        Protect-PrivateFile -LiteralPath $credentialDirectory
        $credentialText = @(
            'SecureFinance ERP - primer acceso privado',
            "Base: $DatabaseName",
            "Usuario: $BootstrapUsername",
            "Clave temporal: $bootstrapPasswordPlain",
            '',
            'La cuenta exige cambiar la contrasena al primer acceso.',
            'Elimine este archivo despues de entregar la credencial por un canal privado.'
        ) -join [Environment]::NewLine
        [IO.File]::WriteAllText($credentialPath, $credentialText + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        Protect-PrivateFile -LiteralPath $credentialPath
    }

    Write-Host "Base instalada sin borrar datos: $DatabaseName"
    Write-Host "Configuracion local: $environmentPath"
    if ($bootstrapAlreadyExists) {
        Write-Host 'La cuenta bootstrap ya existia; su contrasena y su archivo privado no se modificaron.'
    }
    else {
        Write-Host "Primer acceso privado: $credentialPath"
    }
}
finally {
    foreach ($name in $variableNames) {
        [Environment]::SetEnvironmentVariable($name, $previousVariables[$name], 'Process')
    }
    $apiPasswordPlain = $null
    $bootstrapPasswordPlain = $null
}
