# Respaldo y restauración

## Objetivos y límites

- Objetivo de pérdida máxima (RPO): **24 horas**.
- Objetivo de recuperación (RTO): **60 minutos**.
- Copia completa diaria y copia adicional inmediatamente antes de cada migración.
- Conservar al menos siete copias válidas protegidas y una copia verificada en otro medio.
- Restaurar siempre primero con otro nombre de base. Ningún procedimiento de esta guía sobrescribe automáticamente `SecureFinanceERP`.

Estos valores son objetivos QC07, no resultados medidos. Solo una restauración cronometrada y documentada permite informar cumplimiento.

## Responsabilidades

| Rol operativo | Responsabilidad |
|---|---|
| Administrador SQL | Ejecutar/verificar `BACKUP`, controlar restauraciones y permisos. |
| Administrador del equipo | Programar la tarea, proteger carpetas/medio y vigilar capacidad. |
| Responsable de pruebas | Restaurar en base aislada, verificar invariantes y registrar evidencia. |
| Usuario de API | Ninguna: la cuenta de aplicación no recibe permisos `BACKUP`, `RESTORE` ni acceso a archivos de copia. |

## Ubicaciones y seguridad

Use una carpeta dedicada, por ejemplo `C:\SecureFinanceBackups`, que no esté dentro del repositorio, `apps/web/dist` ni el buzón de recuperación. La cuenta del servicio de SQL Server necesita escritura en el destino primario; los usuarios ordinarios y la cuenta de la API no.

Los nombres recomendados son únicos y UTC:

```text
SecureFinanceERP_FULL_20260923T030000Z.bak
SecureFinanceERP_PREMIG_20260923T151500Z.bak
```

No incluya servidor, usuario, contraseña o datos personales en el nombre. Proteja el segundo medio con cifrado del volumen y control de acceso. Si se usa cifrado nativo de backup, custodie certificado y clave privada por separado; una copia sin su material criptográfico no es restaurable.

## Copia completa manual

Antes de ejecutar:

1. confirme instancia y nombre exacto de la base;
2. confirme que la ruta pertenece a la carpeta prevista y tiene espacio suficiente;
3. cree un nombre nuevo; no reutilice ni trunque una copia válida;
4. registre inicio UTC, operador, edición/build de SQL Server y motivo (`DAILY` o `PRE_MIGRATION`).

Ejecute con una cuenta administrativa en SSMS o `sqlcmd`, sustituyendo únicamente la ruta por un nombre nuevo:

```sql
USE master;
GO
DECLARE @Archivo nvarchar(260) =
    N'C:\SecureFinanceBackups\SecureFinanceERP_FULL_20260923T030000Z.bak';

BACKUP DATABASE [SecureFinanceERP]
TO DISK = @Archivo
WITH COPY_ONLY, CHECKSUM, STATS = 5;
GO
```

`COPY_ONLY` evita alterar una estrategia diferencial futura. Puede añadirse `COMPRESSION` solo después de confirmar que la edición/entorno lo admite y de medir CPU/espacio. No use `INIT` sobre una ruta existente.

En PowerShell, una ejecución con autenticación integrada puede invocar un archivo operativo externo al repositorio:

```powershell
$sfSqlInstance = '.\SQLEXPRESS'
$sfBackupScript = 'C:\SecureFinanceOps\Backup-SecureFinance.sql'
sqlcmd -S $sfSqlInstance -E -b -i $sfBackupScript
if ($LASTEXITCODE -ne 0) { throw 'El respaldo de SecureFinance falló.' }
```

No coloque credenciales en la línea de comandos ni dentro de la tarea programada. Si no se usa autenticación integrada, recurra al almacén de secretos autorizado del equipo.

## Verificación inmediata

Que exista un `.bak` no demuestra que sea utilizable. Ejecute sobre el archivo recién creado:

```sql
RESTORE VERIFYONLY
FROM DISK = N'C:\SecureFinanceBackups\SecureFinanceERP_FULL_20260923T030000Z.bak'
WITH CHECKSUM;
GO

RESTORE HEADERONLY
FROM DISK = N'C:\SecureFinanceBackups\SecureFinanceERP_FULL_20260923T030000Z.bak';
GO
```

Registre el resultado, tamaño y un hash SHA-256 calculado después de cerrar el archivo:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\SecureFinanceBackups\SecureFinanceERP_FULL_20260923T030000Z.bak'
```

`VERIFYONLY` comprueba legibilidad/estructura del conjunto, pero no reemplaza una restauración ni `DBCC CHECKDB`.

## Programación diaria en Windows

SQL Server Express no incluye SQL Server Agent. Por tanto, la política no depende de Agent:

1. guarde un script operativo revisado en `C:\SecureFinanceOps` con ACL restringida;
2. cree una cuenta de servicio local con solo los derechos necesarios para iniciar la tarea y conectarse como operador de backup;
3. en **Programador de tareas**, cree una tarea diaria fuera del horario de mayor uso;
4. configure **Ejecutar tanto si el usuario inició sesión como si no**, sin almacenar una contraseña en el script;
5. acción: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy AllSigned -File C:\SecureFinanceOps\Invoke-SecureFinanceBackup.ps1`;
6. haga que el script termine con código distinto de cero ante fallo de `BACKUP`, `VERIFYONLY`, copia secundaria o hash;
7. supervise historial/último resultado y genere una alerta local; una tarea «ejecutada» sin verificar el `.bak` cuenta como fallo.

Si la edición instalada sí dispone de Agent, puede usarse un job equivalente, pero documente cuál mecanismo quedó activo. Nunca programe ambos sin coordinación porque competirían por I/O y retención.

## Retención y segundo medio

- Conserve como mínimo las últimas siete copias diarias verificadas.
- Las copias previas a migración se conservan hasta validar la migración y completar la siguiente restauración periódica.
- Copie al segundo medio solo después de `VERIFYONLY`; vuelva a calcular SHA-256 en el destino y compare.
- No cuente una unidad mapeada que vive en el mismo disco físico como segundo medio.
- Antes de eliminar una copia, resuelva su ruta absoluta, confirme que está dentro de la carpeta exclusiva y que quedan siete copias válidas más la secundaria. Prefiera cuarentena/papelera antes de borrado definitivo.
- Registre creación, verificación, traslado y retiro en un manifiesto sin secretos.

## Restauración aislada

### 1. Preparación

1. declare incidente o ejercicio, inicio UTC y operador;
2. seleccione la última copia válida de acuerdo con manifiesto/hash;
3. reserve un nombre nuevo, por ejemplo `SecureFinanceERP_Restore_20260923`;
4. confirme que `DB_ID(N'SecureFinanceERP_Restore_20260923') IS NULL`;
5. no cambie `DB_NAME` de la API y no permita que usuarios normales entren a la base restaurada;
6. identifique nombres lógicos, sin adivinarlos:

```sql
RESTORE FILELISTONLY
FROM DISK = N'C:\SecureFinanceBackups\SecureFinanceERP_FULL_20260923T030000Z.bak';
GO
```

### 2. Restaurar con otro nombre

Sustituya `SecureFinanceERP`/`SecureFinanceERP_log` por los nombres lógicos devueltos y use rutas de datos autorizadas para la instancia:

```sql
USE master;
GO
IF DB_ID(N'SecureFinanceERP_Restore_20260923') IS NOT NULL
    THROW 51006, N'La base de destino ya existe; elija otro nombre.', 1;
GO

RESTORE DATABASE [SecureFinanceERP_Restore_20260923]
FROM DISK = N'C:\SecureFinanceBackups\SecureFinanceERP_FULL_20260923T030000Z.bak'
WITH
    MOVE N'SecureFinanceERP' TO N'C:\SecureFinanceRestore\SecureFinanceERP_Restore_20260923.mdf',
    MOVE N'SecureFinanceERP_log' TO N'C:\SecureFinanceRestore\SecureFinanceERP_Restore_20260923_log.ldf',
    CHECKSUM,
    RECOVERY,
    STATS = 5;
GO
```

No añada `WITH REPLACE`; no restaure encima de producción durante una prueba. Si hay más archivos en `FILELISTONLY`, proporcione un `MOVE` único para cada uno.

### 3. Invalidar credenciales recuperadas

Una copia puede contener sesiones y tokens que eran válidos cuando se creó. Antes de conectar una API de verificación, ejecute dentro de la base restaurada:

```sql
USE [SecureFinanceERP_Restore_20260923];
GO
BEGIN TRANSACTION;
    UPDATE dbo.Sesion
       SET RevocadaUtc = COALESCE(RevocadaUtc, SYSUTCDATETIME());

    UPDATE dbo.TokenRecuperacion
       SET RevocadoUtc = COALESCE(RevocadoUtc, SYSUTCDATETIME())
     WHERE UsadoUtc IS NULL;
COMMIT TRANSACTION;
GO
```

Esto forma parte del ejercicio de recuperación y debe constar en el acta. No crea ni publica una contraseña de administrador.

### 4. Integridad técnica

```sql
DBCC CHECKDB (N'SecureFinanceERP_Restore_20260923') WITH NO_INFOMSGS, ALL_ERRORMSGS;
GO
```

Confirme también nivel de compatibilidad, objetos esperados y que la base está `ONLINE`. Un `CHECKDB` sin mensajes no demuestra por sí solo la coherencia funcional.

### 5. Verificación funcional mínima

En la base restaurada y con datos sintéticos conocidos, registre conteos y muestras sin copiar secretos:

```sql
USE [SecureFinanceERP_Restore_20260923];
GO
SELECT COUNT_BIG(*) AS Usuarios FROM dbo.Usuario;
SELECT COUNT_BIG(*) AS Facturas FROM dbo.Factura;
SELECT COUNT_BIG(*) AS Detalles FROM dbo.Detalle_Factura;

SELECT f.FacturaId, f.Numero, f.Subtotal, f.IVA, f.Total,
       COUNT_BIG(d.DetalleFacturaId) AS Lineas,
       COUNT_BIG(mc.MovimientoCajaId) AS MovimientosCaja
FROM dbo.Factura AS f
LEFT JOIN dbo.Detalle_Factura AS d ON d.FacturaId = f.FacturaId
LEFT JOIN dbo.MovimientoCaja AS mc ON mc.FacturaId = f.FacturaId
WHERE f.FacturaId = @FacturaPruebaId
GROUP BY f.FacturaId, f.Numero, f.Subtotal, f.IVA, f.Total;

SELECT ProductoId, Codigo, Stock
FROM dbo.Producto
WHERE ProductoId = @ProductoPruebaId;
GO
```

Además verifique que:

- las cuentas de prueba esperadas existen y sus roles concuerdan;
- la factura elegida conserva encabezado y líneas históricas;
- tiene exactamente un movimiento de caja por el total esperado;
- el stock del producto concuerda con la venta/ajustes registrados;
- no existe stock negativo;
- todos los objetos/SP requeridos están presentes;
- sesiones y tokens no usados quedaron revocados.

No inicie sesión con contraseñas tomadas de consultas ni extraiga `PasswordHash`, `PasswordSalt`, `SesionHash` o `TokenHash` como evidencia.

## Medición de QC07 / PA31

Registre al menos:

| Campo | Valor de la corrida |
|---|---|
| ID de ejercicio | — |
| Estado | Pendiente |
| Inicio de incidente/restauración UTC | — |
| Hora del último backup válido UTC | — |
| Fin de recuperación/verificación UTC | — |
| Pérdida calculada | — |
| Duración calculada | — |
| Archivo y SHA-256 | — |
| Base de destino | — |
| `VERIFYONLY` / `CHECKDB` | — |
| Factura/producto sintético verificado | — |
| Sesiones/tokens invalidados | — |
| Evidencia | — |
| Responsable/incidencia | — |

La pérdida se calcula entre el último dato confirmado que debía recuperarse y el punto real del backup; la duración va desde la declaración del ejercicio hasta que las verificaciones acordadas terminan. No reste tiempos manualmente para mejorar el resultado.

## Promoción tras un incidente real

La decisión de sustituir una base dañada es administrativa y queda fuera de una restauración de prueba. Requiere autorización, ventana de mantenimiento, detener escrituras, preservar la base/archivos originales, confirmar cadenas de conexión, plan de reversión y comunicación a usuarios. Esta guía no autoriza `DROP DATABASE`, `WITH REPLACE` ni cambios automáticos de la API hacia una copia restaurada.

## Lista de comprobación

- [ ] Copia completa diaria con nombre único.
- [ ] Copia previa a migración.
- [ ] `CHECKSUM`, `VERIFYONLY`, tamaño y SHA-256 registrados.
- [ ] Al menos siete copias protegidas.
- [ ] Copia verificada en otro medio.
- [ ] Tarea supervisada y fallo visible.
- [ ] Restauración periódica con otro nombre.
- [ ] `DBCC CHECKDB` y verificación funcional.
- [ ] Sesiones/tokens restaurados revocados.
- [ ] RPO/RTO medidos, no inferidos.
- [ ] Evidencia sin secretos enlazada a PA31/QC07.

El estado inicial de PA31 y QC07 es **Pendiente**.
