# SecureFinance ERP - base de datos

Los scripts usan modo SQLCMD y no se ejecutan al arrancar la API. La instalacion crea objetos faltantes y usa `CREATE OR ALTER` para codigo SQL; no elimina tablas, datos ni bases existentes.

## Instalacion

Ejecutar desde la raiz del repositorio y proporcionar siempre el destino de forma explicita:

```powershell
sqlcmd -S '.\SQLEXPRESS' -E -b -v DatabaseName="SecureFinanceERP_Test" -i .\database\install.sql
```

`install.sql` no define un valor predeterminado para `DatabaseName`. SQL Server 2022 usa compatibilidad 160 y SQL Server 2025 usa 170. La configuracion persistida inicial es moneda `GTQ`, zona de aplicacion `America/Guatemala`, zona SQL `Central America Standard Time` e IVA `0.120000`; una factura conserva esos valores como snapshot.

El instalador registra `0001_baseline` y `0002_security_contract_hardening` en `dbo.SchemaMigration`. La segunda migración retira `VENTAS_CREAR` de roles administradores existentes, elimina texto DDL legado y normaliza restricciones de seguridad. Las migraciones futuras son incrementales y nunca deben borrar o volver a sembrar una base durante el arranque habitual.

## Identidades iniciales

El instalador base no crea logins ni credenciales. Aprovisionar el login tecnico con valores privados validados por el instalador de operacion:

```powershell
sqlcmd -S '.\SQLEXPRESS' -E -b `
  -v DatabaseName="SecureFinanceERP_Test" ApiLoginName="SecureFinanceApi" ApiLoginPassword="<secreto-privado>" `
  -i .\database\provision-api-login.sql
```

Después, crear una unica cuenta bootstrap. Si ya existe, el script conserva su hash y no restablece su clave:

```powershell
sqlcmd -S '.\SQLEXPRESS' -E -b `
  -v DatabaseName="SecureFinanceERP_Test" BootstrapUsername="admin.local" BootstrapDisplayName="Administrador local" BootstrapPassword="<temporal-privada>" `
  -i .\database\provision-bootstrap-admin.sql
```

El rol de base `SecureFinanceApiExecutor` recibe solo `EXECUTE` sobre procedimientos invocados por la API y `EXECUTE`/`REFERENCES` sobre los tres TVP necesarios. Tiene denegado DML directo y no recibe DDL, lectura de tablas ni acceso a secretos.

## Datos demo

`seed-demo.sql` esta separado y se niega a operar salvo que el nombre de la BD termine en `_Test`. Inserta roles Cajero/Auditor, un cliente y dos productos; la carga de stock queda registrada como movimiento.

## Auditoria

Los triggers DML funcionan por conjuntos. Hashes, salts, tokens y hashes de sesion se excluyen de los snapshots. El trigger DDL no conserva `TSQLCommand`: almacena un XML reducido a metadatos para evitar persistir contrasenas incluidas en sentencias DDL.

## Validacion y operacion

- `tests/parse-only.sql`: analisis sintactico no mutante mediante `SET PARSEONLY`.
- `tests/01_contract.sql`: inventario de objetos y firmas una vez instalada una BD de prueba.
- `tests/02_pool_identity_pa29.sql`: limpia contexto residual aun cuando una sesion sea invalida.
- `tests/03_save-transaction.sql`: demostracion aislada de punto de guardado.
- `tests/04_sale-rollback-fault.sql`: fallo posterior al encabezado mediante un trigger transaccional con nombre único; verifica ausencia de filas de factura, detalle, caja, auditoría y fixtures. Los huecos de `IDENTITY`/secuencia tras rollback son esperados.
- `operations/backup.sql`, `verify-backup.sql` y `restore-to-verification.sql`: copia y restauracion verificable en una BD separada.

Los resultados PA/QC solo pueden marcarse cumplidos despues de ejecutar y conservar evidencia; la presencia de estos scripts no constituye evidencia por si sola.
