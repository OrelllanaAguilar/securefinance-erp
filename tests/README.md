# Pruebas de SecureFinance ERP

Las suites se separan porque una prueba simulada no demuestra el comportamiento de SQL Server.

## Rápidas y aisladas

```powershell
pnpm lint
pnpm test
pnpm build
```

Estas órdenes comprueban esquemas HTTP, controles de seguridad, utilidades de importes, componentes y compilación. No autorizan marcar PA01–PA32 como aprobadas.

## SQL Server real

Prepare una base terminada en `_Test`, nunca una base con datos reales:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-Database.ps1 `
  -DatabaseName 'SecureFinanceERP_Integration_Test' `
  -ApiLoginName 'SecureFinanceApiIntegration' `
  -IncludeDemoData

pnpm sql:verify
$env:RUN_SQL_INTEGRATION='true'; pnpm test:integration; Remove-Item Env:RUN_SQL_INTEGRATION
sqlcmd -S '.\SQLEXPRESS' -E -C -b -v DatabaseName='SecureFinanceERP_Integration_Test' -i .\database\tests\01_contract.sql
sqlcmd -S '.\SQLEXPRESS' -E -C -b -v DatabaseName='SecureFinanceERP_Integration_Test' -i .\database\tests\02_pool_identity_pa29.sql
sqlcmd -S '.\SQLEXPRESS' -E -C -b -v DatabaseName='SecureFinanceERP_Integration_Test' -i .\database\tests\03_save-transaction.sql
sqlcmd -S '.\SQLEXPRESS' -E -C -b -v DatabaseName='SecureFinanceERP_Integration_Test' -i .\database\tests\04_sale-rollback-fault.sql
```

Con la API levantada sobre esa misma base, `pnpm test:smoke` ejecuta un recorrido HTTP real. Se niega a operar si `DB_NAME` no termina en `_Test`, lee la credencial desde `secrets/` sin mostrarla y deja un acta sanitizada en `docs/evidence/runtime/`. Es una comprobación de integración; por sí sola no cubre una PA completa ni concurrencia real.

El script `04` cubre un fallo concreto después del encabezado y elimina automáticamente su trigger y fixtures. Las carreras, otros puntos de rollback, recuperación concurrente, idempotencia concurrente, cambio de permisos y dataset QC requieren datos exclusivos y coordinación. Registre cada ejecución mediante [la guía de evidencia](../docs/evidence-guide.md); no reutilice un resultado de otra versión.

## Interfaz

Con la aplicación compilada y levantada en `127.0.0.1:3000`:

```powershell
pnpm test:e2e
pnpm test:smoke
pnpm test:e2e:private
```

Las pruebas públicas no necesitan credenciales y usan Vite Preview. El humo real debe ejecutarse antes del recorrido privado: crea cuentas/datos sintéticos y guarda la credencial vigente en `secrets/test-current-access.json`, ignorado por Git y con acceso local restringido. Playwright privado se niega a operar si `.env` no apunta a una base `_Test`, usa la aplicación integrada en `127.0.0.1:3000`, no genera `storageState`, trazas ni vídeo y enmascara la cuenta en las capturas.

Revise manualmente acceso, inicio, nueva venta, comprobante y administración en Claro/Oscuro, anchos 320/768/1280 y texto al 200 %. Una captura debe ocultar nombres, correo, enlaces de recuperación, cookies y contraseñas.

## Resultados oficiales

El estado oficial está en [PA01–PA32](../docs/test-matrix.md). Cada cambio de `Pendiente` exige fecha, entorno, datos, resultado observado y ruta de evidencia. Los objetivos QC01–QC08 necesitan el volumen y las cinco sesiones definidos por la especificación; una ejecución con la semilla pequeña no los mide.
