# Verificación técnica ejecutada

## Alcance y advertencia

Este registro resume comprobaciones parciales ejecutadas el **24 de septiembre de 2026** sobre el workspace local. No es un manifiesto formal de aceptación, no certifica seguridad ni producción y **no cambia PA01–PA32 ni QC01–QC08 de Pendiente**. El workspace no contiene metadatos Git, por lo que la corrida queda ligada a estos archivos locales y no a un commit identificable.

## Entorno observado

| Componente | Valor |
|---|---|
| Sistema operativo | Windows 11 Home `10.0.26200`, build `26200` |
| PowerShell | `5.1.26100.9444` |
| Node.js | `v24.18.0` |
| pnpm | `10.34.4` |
| SQL Server | `17.0.1000.7` RTM, Express Edition 64-bit |
| Instancia administrativa | `.\SQLEXPRESS` |
| Base exclusiva | `SecureFinanceERP_Verification_20260923_Test` |
| Navegador automatizado | Microsoft Edge `153.0.4234.48` |
| Origen integrado | `http://127.0.0.1:3000` |

No se incluyen contraseñas, cookies, hashes, tokens ni cadenas de conexión.

## Resultados observados

| Comprobación | Resultado | Alcance real |
|---|---|---|
| `pnpm install --frozen-lockfile` | Aprobó; lockfile vigente | Reproducibilidad de dependencias en este workspace, con caché/entorno actuales. |
| `pnpm audit --prod` | Sin vulnerabilidades conocidas informadas | Consulta puntual al registro; no es auditoría de código ni garantía futura. |
| ACL de `.env`, `secrets/` y `private-mailbox/` | Solo el usuario actual conserva `FullControl` en el entorno observado | Comprobación local de ACL; debe repetirse después de copiar o restaurar archivos. |
| `pnpm lint` | Aprobó API y web | Reglas estáticas configuradas. |
| `pnpm test` | 16 API + 24 web = **40 aprobadas**; 3 SQL condicionales omitidas en esta orden | Unitarias/aisladas y regresiones de configuración, conexión, seguridad, componentes y formatos. |
| `pnpm build` | Aprobó | Bundle Vite de producción generado. |
| `pnpm sql:verify` | `available`, `GTQ`, `America/Guatemala` | Conectividad y ejecución de `sp_VerificarEstado` con el login mínimo de la API. |
| `RUN_SQL_INTEGRATION=true; pnpm test:integration` | **3 aprobadas** | SP concedido; lectura/escritura directa y SP interno denegados al login API. |
| `database/tests/01_contract.sql` | `ok` | Objetos, migraciones, triggers, tipos, permisos TVP y casos decimales puntuales. |
| `database/tests/02_pool_identity_pa29.sql` | `ok` | Limpieza de cinco claves de contexto ante sesión inválida; no cubre alternancia concurrente real. |
| `database/tests/03_save-transaction.sql` | `ok` | Demostración aislada de savepoint y cierre de transacción. |
| `database/tests/04_sale-rollback-fault.sql` | `ok` | Fallo posterior al encabezado; ausencia de filas parciales, trigger y fixtures; incidente separado comprobado y limpiado. Los contadores `IDENTITY` y la secuencia pueden dejar huecos esperados. |
| `pnpm test:smoke` | Aprobó, 21 intercambios HTTP | Cambio inicial, revocación, permisos, inventario, tema, cotización `100.00/12.00/112.00`, venta, caja, reporte e idempotencia secuencial. |
| `pnpm test:e2e` | **19 aprobadas** | Tres páginas públicas, Claro/Oscuro, 320/768/1280, Axe, CSP y ausencia de errores del navegador. |
| `pnpm test:e2e:private` | **1 recorrido aprobado; 14 vistas capturadas** | Administrador/escritorio/claro y Cajero/móvil/oscuro contra API/SQL reales; Axe, desbordamiento y errores de consola. |
| Inspección visual puntual | Sin defecto abierto en las capturas revisadas | Inicio, roles, nueva venta y comprobante; la cuenta se enmascara deliberadamente en las imágenes. |

La evidencia sanitizada de humo y las capturas se guardan localmente bajo `docs/evidence/runtime/`, directorio excluido del control de versiones. Para una aceptación formal deben copiarse a un paquete controlado, incluir hashes/manifiesto, revisión identificable, salida íntegra y ejecutor.

## Defectos encontrados y corregidos durante la corrida

- `mssql` intentaba mutar una configuración congelada; ahora recibe una copia mutable.
- El timeout especial de venta usaba una propiedad ignorada; ahora se pasa como `requestTimeout` soportado por el driver.
- Los booleanos predeterminados de Zod podían conservar cadenas truthy; ahora siempre se transforman y hay regresión automatizada.
- Los marcadores de secretos de `.env.example` se rechazan al arrancar.
- El editor de roles evaluaba una cuenta nula cuando el modal estaba cerrado.
- Se corrigieron contraste de botones deshabilitados, nombre accesible del menú móvil y fondo del detalle del comprobante oscuro.
- El botón de menú móvil dejó de mostrarse en escritorio.
- La prueba de rollback ya no deja lógica de test en el SP ni filas sintéticas persistentes; como en cualquier rollback con `IDENTITY`/secuencias, los contadores pueden avanzar.

## Cobertura aún pendiente

- Carreras reales de stock, recuperación y misma clave mediante clientes simultáneos.
- Alternancia de identidades/cancelación sobre una única conexión física del pool.
- Dataset QC y carga de cinco sesiones con percentiles.
- Teclado completo, zoom 200 %, todos los diálogos/estados y matriz de navegadores.
- Desconexión de Internet y reinstalación/reinicio desde una copia limpia.
- Respaldo y restauración cronometrados con RPO/RTO y `DBCC CHECKDB` sobre la copia.
- Revisión de seguridad independiente, TLS local y migración del hash académico a un verificador con factor de trabajo.

Por estas limitaciones, la matriz oficial permanece sin resultados aprobados.
