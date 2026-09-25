$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $projectRoot 'database\SecureFinanceERP_Unificado.sql'

$sourceFiles = @(
    'database\00_database.sql'
    'database\01_schema.sql'
    'database\02_functions.sql'
    'database\03_security.sql'
    'database\04_catalogs.sql'
    'database\05_sales_reports.sql'
    'database\06_audit.sql'
    'database\07_permissions.sql'
    'database\migrations\0002_security_contract_hardening.sql'
    'database\provision-bootstrap-admin.sql'
    'database\seed-demo.sql'
)

$header = @'
/*
    SecureFinance ERP - Script SQL unificado

    Contenido:
      - Creacion y configuracion de la base de datos.
      - Tablas, llaves primarias/foraneas, restricciones e indices.
      - Funciones escalares y funciones con valor de tabla (TVF).
      - Stored Procedures, triggers DML/DDL, roles y permisos internos.
      - Usuario administrador bootstrap y datos semilla demostrativos.

    Requisitos:
      - SQL Server 2022 (16.x) o posterior.
      - Ejecutar con SQLCMD desde la raiz del repositorio.
      - DatabaseName debe terminar en _Test porque incluye datos demo.
      - La clave bootstrap debe tener 12-128 caracteres, mayuscula,
        minuscula, numero y simbolo.

    Ejemplo:
      sqlcmd -S ".\SQLEXPRESS" -E -C -b `
        -v DatabaseName="SecureFinanceERP_Entrega_Test" `
           BootstrapUsername="admin.local" `
           BootstrapDisplayName="AdministradorLocal" `
           BootstrapPassword="REEMPLAZAR_POR_CLAVE_SEGURA" `
        -i ".\database\SecureFinanceERP_Unificado.sql"

    El script es idempotente: conserva datos existentes y no elimina la base.
    Si el usuario bootstrap ya existe, no cambia su contrasena.
*/

:on error exit
PRINT N'Iniciando instalacion unificada de SecureFinance ERP...';
GO
'@

$footer = @'

USE [$(DatabaseName)];
GO

IF NOT EXISTS (SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId = '0001_baseline')
    THROW 51006, N'La migracion base no quedo registrada.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId = '0002_security_contract_hardening')
    THROW 51006, N'La migracion de seguridad no quedo registrada.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE EsAdministrador = 1 AND Activo = 1)
    THROW 51006, N'No se creo o encontro el rol administrador activo.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE NombreUsuario = '$(ESCAPE_SQUOTE(BootstrapUsername))' AND Activo = 1)
    THROW 51006, N'No se creo o encontro el usuario bootstrap activo.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Codigo IN ('DEMO-001', 'DEMO-002'))
    THROW 51006, N'Los productos semilla no quedaron disponibles.', 1;
GO

PRINT N'Instalacion unificada de SecureFinance ERP completada correctamente.';
GO
'@

$builder = [System.Text.StringBuilder]::new()
[void]$builder.AppendLine($header.TrimEnd())

foreach ($relativePath in $sourceFiles) {
    $fullPath = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "No se encontro el modulo SQL requerido: $relativePath"
    }

    [void]$builder.AppendLine()
    [void]$builder.AppendLine("/* ===== INICIO: $relativePath ===== */")
    [void]$builder.AppendLine([System.IO.File]::ReadAllText($fullPath).Trim())
    [void]$builder.AppendLine("/* ===== FIN: $relativePath ===== */")
}

[void]$builder.AppendLine($footer.TrimStart())
[System.IO.File]::WriteAllText(
    $outputPath,
    $builder.ToString(),
    [System.Text.UTF8Encoding]::new($false)
)

$file = Get-Item -LiteralPath $outputPath
Write-Host "Generado: $($file.FullName) ($($file.Length) bytes)"
