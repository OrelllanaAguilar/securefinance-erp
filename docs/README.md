# Documentación de SecureFinance ERP

Esta carpeta documenta la versión 2.0 de SecureFinance ERP y su implementación local con React, Express, Node.js y Microsoft SQL Server. Es una entrega académica/local: **no está declarada, certificada ni preparada para producción**.

La referencia funcional `SecureFinance_ERP_Casos_de_Uso (1).pdf` se contrastó desde su ubicación externa en `Downloads`; no se copia al workspace. Los UC01–UC14, PA01–PA32 y QC01–QC08 resumidos en estos documentos mantienen esa línea base, pero la aceptación formal sigue requiriendo ejecutar y firmar sus protocolos.

## Fuentes y criterio de verdad

| Pregunta | Fuente autoritativa en esta entrega |
|---|---|
| ¿Qué comportamiento se exige? | Especificación funcional y resultados esperados PA/QC. El código no puede rebajar una expectativa. |
| ¿Qué está implementado ahora? | Archivos versionados de `apps/`, `database/` y `scripts/`, contrastados con contratos y trazabilidad. |
| ¿Qué ocurrió realmente al ejecutar? | Registro de corrida y archivos enlazados desde [Matriz PA01–PA32](test-matrix.md), conforme a la [Guía de evidencia](evidence-guide.md). |

Una relación en la trazabilidad o la presencia de un SP demuestra cobertura estática, no comportamiento observado. Si estas tres capas discrepan, se registra el hueco; no se convierte la intención en evidencia.

## Estado de verificación

- PA01–PA32 permanecen **Pendiente** en el registro oficial.
- QC01–QC08 permanecen **Pendiente** y son objetivos; no contienen resultados ni métricas inferidas.
- No existe un manifiesto de evidencia de runtime bajo `docs/evidence/`. Las salidas de lint, pruebas aisladas o compilación que se ejecuten fuera de ese flujo no cambian por sí solas una PA/QC.
- La documentación distingue diseño, procedimiento de prueba y resultado observado. Leer código no equivale a aprobar una prueba.
- `GET /api/health` y `pnpm sql:verify` son comprobaciones de conectividad, no una certificación funcional, de seguridad, continuidad u operación offline.

### Inventario estático contrastado

La inspección del código fuente encontró 41 procedimientos, 6 funciones, 4 tipos de tabla y 11 triggers SQL. El rol `SecureFinanceApiExecutor` recibe 36 SP públicos; los otros 5 SP son internos. La API expone 36 operaciones HTTP concretas si las tres categorías de auditoría se cuentan por separado. Estos conteos sirven para detectar deriva documental; no prueban que una instalación haya sido ejecutada correctamente.

### Cobertura automatizada y huecos conocidos

- Playwright cubre las tres páginas públicas en Claro/Oscuro y 320/768/1280. Una configuración separada recorre 14 vistas privadas contra API y SQL reales, con cuentas sintéticas de una base `_Test`, dos roles, dos temas, comprobación Axe y capturas en `docs/evidence/runtime/ui/`. Es cobertura parcial: no sustituye teclado/zoom completo, diálogos en edición ni toda PA13–PA25.
- `pnpm test:integration`, habilitado con `RUN_SQL_INTEGRATION=true`, comprueba con el login real de la API el SP autorizado y la denegación de lectura, escritura y procedimientos internos. No sustituye las carreras ni el aislamiento completo de PA29.
- No hay generador del dataset QC de 1,000 clientes, 10,000 productos, 50,000 facturas y 250,000 líneas, ni arnés de carga de cinco sesiones; PA30/QC01/QC02 no son ejecutables con el volumen prescrito tal como está empaquetado.
- `database/tests/04_sale-rollback-fault.sql` inyecta un fallo después del encabezado mediante un trigger temporal, exclusivamente con conexión administrativa y base `_Test`; la misma reversión elimina trigger y fixtures. Demuestra un punto concreto, no toda la matriz de fallos de PA06/QC03.
- Los scripts de respaldo/restauración y las pruebas SQL son herramientas de ejecución; sin acta, salida íntegra y evidencia enlazada no demuestran PA29, PA31 ni QC07.

## Requisitos de instalación

- Windows con PowerShell 7 o Windows PowerShell 5.1.
- Node.js `>=24.18.0 <25` y pnpm `10.34.4`, exactamente como declara `package.json`.
- Microsoft SQL Server 2022 (16.x) o posterior. El script selecciona compatibilidad 160 para 2022 y 170 para 2025 o posterior.
- `sqlcmd` disponible en `PATH`, con soporte de modo SQLCMD y de la opción `-C` usada por los scripts.
- Una cuenta Windows con autenticación integrada y autoridad para crear la base, el login SQL y el usuario de base.
- Autenticación SQL habilitada y TCP local configurado para que la API use el login de mínimo privilegio. Los valores predeterminados esperan administración en `.\SQLEXPRESS` y aplicación en `127.0.0.1:1433`; adapte instancia/puerto a la configuración real.
- La instancia debe exponer `Central America Standard Time` en `sys.time_zone_info`, condición que el instalador comprueba antes de crear la configuración de Guatemala.
- Un navegador actual para uso interactivo. La suite E2E incluida usa el canal local `msedge`; no se declara una matriz de navegadores aprobada hasta ejecutar PA24.

Los 16 GB de RAM y SSD de [Plan de calidad](quality-plan.md) pertenecen al equipo de referencia para rendimiento; no son un mínimo funcional demostrado. Se necesita Internet para obtener dependencias la primera vez. El funcionamiento posterior sin Internet sigue siendo el objetivo de PA26/PA32, no un resultado registrado.

## Instalación local reproducible

Desde la raíz del repositorio:

```powershell
pnpm install --frozen-lockfile

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-Database.ps1 `
  -AdminServerInstance '.\SQLEXPRESS' `
  -ApplicationServer '127.0.0.1' `
  -ApplicationPort 1433 `
  -DatabaseName 'SecureFinanceERP' `
  -ApiLoginName 'SecureFinanceApi'
```

Para una base nueva, si se omiten `ApiSqlPassword` y `BootstrapPassword`, el helper genera valores aleatorios. La secuencia implementada es:

1. `database/install.sql`: base, esquema, funciones, SP, triggers, rol y permisos;
2. `database/provision-api-login.sql`: login/usuario SQL dedicado y pertenencia a `SecureFinanceApiExecutor`; una identidad preexistente debe auditarse porque el script no retira privilegios ajenos;
3. `database/provision-bootstrap-admin.sql`: primer administrador con cambio obligatorio;
4. opcionalmente `database/seed-demo.sql`, solo con `-IncludeDemoData` y un nombre terminado en `_Test`;
5. `.env` y, para una cuenta bootstrap nueva, `secrets/first-access.txt` con intento de ACL restringida al usuario actual.

No copie a evidencia ni al repositorio `.env`, `secrets/`, `private-mailbox/`, contraseñas o tokens. Revise cualquier advertencia de ACL y elimine `secrets/first-access.txt` después de entregar la credencial por un canal privado y completar el primer cambio de contraseña.

El helper no modifica una base existente sin `-AllowExisting`. En ese modo exige la contraseña SQL conocida mediante `-ApiSqlPassword` como `SecureString`, no recupera secretos y no restablece una cuenta bootstrap existente. Haga copia previa y trate cualquier cambio de esquema como migración administrativa; que los scripts sean reejecutables no sustituye un plan de migración.

Para desarrollo:

```powershell
pnpm dev
```

Abra `http://127.0.0.1:5173`. Para ejecución integrada de un solo origen:

```powershell
pnpm build
pnpm start
```

Abra `http://127.0.0.1:3000`. Los valores predeterminados son HTTP local, cookie no `Secure`, certificado SQL confiado explícitamente y buzón de recuperación en archivo; son elecciones de laboratorio, no una configuración productiva.

### Comprobaciones posteriores y su alcance

```powershell
pnpm lint
pnpm test
pnpm build
pnpm sql:verify
pnpm test:e2e
$env:RUN_SQL_INTEGRATION='true'; pnpm test:integration; Remove-Item Env:RUN_SQL_INTEGRATION
pnpm test:smoke
pnpm test:e2e:private
```

- `lint`, Vitest y `build` comprueban calidad estática, pruebas aisladas y compilación según las suites presentes.
- `sql:verify` usa `.env` y ejecuta únicamente `dbo.sp_VerificarEstado` con la cuenta API.
- `test:e2e` ejecuta únicamente el humo público descrito arriba con sesión simulada y Microsoft Edge; no usa el login, la API integrada ni la base real.
- `test:integration`, `test:smoke` y `test:e2e:private` requieren la base `_Test` preparada. El humo crea datos sintéticos y guarda las credenciales vigentes bajo `secrets/`; el recorrido privado no escribe credenciales, cookies, trazas ni vídeo.
- Las pruebas de `database/tests/` se ejecutan expresamente contra una base `_Test` con una cuenta administrativa y conservando salida/código de retorno. Su mera presencia no cambia el estado PA.

## Índice

| Documento | Contenido |
|---|---|
| Este README | Estado real, requisitos, instalación y huecos de verificación. |
| [Arquitectura](architecture.md) | Componentes, límites de confianza, flujos y ejecución local. |
| [ERD físico](physical-erd.md) | Entidades, claves, relaciones, restricciones e índices principales. |
| [Catálogo SQL](stored-procedures.md) | Tipos, funciones, procedimientos, triggers y permisos. |
| [Contratos API](api-contracts.md) | Autenticación, errores, paginación y endpoints HTTP. |
| [Decisiones técnicas](technical-decisions.md) | Seguridad, SHA2_512 académico, sesiones, TVP, importes y auditoría. |
| [Trazabilidad](traceability.md) | UC → pantalla → endpoint → procedimiento → PA. |
| [Manual de usuario](user-manual.md) | Operación por módulo, temas Claro/Oscuro/Sistema y resolución de estados. |
| [Respaldo y restauración](backup-restore.md) | Copias, retención, restauración aislada y acta RPO/RTO. |
| [Matriz PA01–PA32](test-matrix.md) | Escenario, resultado esperado y campos de ejecución. |
| [Plan QC01–QC08](quality-plan.md) | Dataset, mediciones, percentiles y criterios de calidad. |
| [Guion de demostración](demo-script.md) | Recorrido cronometrado de doce minutos. |
| [Guía de evidencia](evidence-guide.md) | Capturas, registros, redacción y manifiesto verificable. |
| [Verificación técnica ejecutada](verification-results.md) | Comprobaciones parciales observadas en el entorno local, sin cambiar el estado PA/QC. |

## Convenciones

- Fechas almacenadas: UTC; presentación: `dd/mm/aaaa`, hora de 24 horas en `America/Guatemala` para la configuración de demostración.
- Moneda de demostración: `GTQ`, siempre con código y dos decimales.
- Los importes viajan por HTTP como cadenas decimales; SQL Server conserva `DECIMAL(19,2)`.
- Identificadores de correlación: UUID en `X-Correlation-Id` y en las respuestas de error.
- Los ejemplos que contienen nombres de servidor, rutas o cuentas son marcadores y deben adaptarse sin incluir secretos.
