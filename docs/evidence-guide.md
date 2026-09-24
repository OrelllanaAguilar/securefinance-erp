# Guía de evidencia

## Principios

La evidencia demuestra una ejecución, no una intención. Debe ser reproducible, estar vinculada a una PA/QC y conservar contexto suficiente para que otra persona verifique el resultado.

- No fabricar capturas, salidas ni fechas.
- No usar una captura de código como prueba de comportamiento.
- No incluir contraseñas, cookies, tokens, hashes, salts, cadenas de conexión, claves privadas, datos personales reales ni rutas privadas innecesarias.
- Mantener el identificador de correlación cuando ayude a unir UI, API y bitácora.
- Una evidencia fallida se conserva y se enlaza con la incidencia; no se reemplaza silenciosamente.
- Conservar el comando o pasos exactos, código de salida y revisión del código. Una captura aislada sin esas referencias no acredita una corrida reproducible.
- Acreditar cada resultado esperado de la PA. Un caso feliz no aprueba escenarios negativos, concurrencia, límites o persistencia incluidos en la misma fila.

## Estado actual y clases de comprobación

No existe actualmente `docs/evidence/manifest.csv` ni un paquete de evidencia de runtime registrado. Por tanto, PA01–PA32 y QC01–QC08 permanecen **Pendiente**.

| Clase | Ejemplos | Qué permite afirmar |
|---|---|---|
| Inspección estática | leer rutas, SP, permisos, esquema y documentación | Que existe una implementación diseñada; nunca que se ejecutó correctamente. |
| Verificación aislada | lint, Vitest con mocks, build, análisis sintáctico SQL | Solo la propiedad concreta comprobada por esa herramienta y revisión. No acredita ACID, permisos SQL reales, UI completa ni PA/QC. |
| Smoke test | `GET /api/health`, `pnpm sql:verify` | Conectividad inmediata y acceso a `sp_VerificarEstado`; no salud integral. |
| Ejecución PA/QC | sistema real, datos/precondiciones prescritos, observaciones y artefactos | Puede cambiar el estado únicamente cuando cubre todos los resultados esperados y queda enlazada en el registro oficial. |

Una salida de consola generada durante desarrollo no se convierte retroactivamente en evidencia oficial si no conserva entorno, revisión, datos, comando, hora y archivo íntegro. Puede repetirse bajo el protocolo y registrarse entonces.

## Estructura recomendada

```text
docs/evidence/
  manifest.csv
  PA05/
    AAAAMMDDThhmmssZ-venta-correcta.png
    AAAAMMDDThhmmssZ-verificacion-sql.txt
  QC01/
    run-001-environment.md
    run-001-raw.csv
    run-001-summary.json
```

No se crea contenido dentro de `docs/evidence/` hasta disponer de una ejecución real. Los nombres usan UTC y no contienen nombres de personas.

## Manifiesto mínimo

| Campo | Descripción |
|---|---|
| `evidence_id` | Identificador único estable. |
| `test_id` | PA01–PA32 o QC01–QC08. |
| `captured_at_utc` | Instante ISO 8601. |
| `environment_id` | Referencia al acta de entorno. |
| `revision` | Commit, hash de paquete o identificador inmutable del código ejecutado. |
| `actor_role` | Rol sintético usado, no nombre real. |
| `action` | Qué se ejecutó. |
| `command_or_steps` | Comando exacto o referencia a pasos numerados. |
| `exit_code` | Código de salida, cuando aplique; no se omite un fallo. |
| `expected` | Resultado esperado relevante. |
| `observed` | Resultado realmente observado. |
| `file` | Ruta relativa. |
| `sha256` | Hash del archivo después de redactar. |
| `redactions` | Qué se ocultó y por qué. |
| `correlation_id` | Solo si no constituye un secreto y es útil. |
| `executor` | Responsable de la corrida. |

## Capturas de interfaz

Para acceso, inicio, venta, comprobante y módulos administrativos registrar:

- tema y preferencia (`Claro`, `Oscuro` o `Sistema`);
- viewport exacto 320, 768 o 1280 px y escala/zoom;
- navegador/versión;
- estado probado: carga, vacío, sin coincidencias, éxito, validación, conflicto o servicio caído;
- elemento enfocado cuando la prueba sea de teclado;
- consola sin errores inesperados, en una evidencia separada si es necesario.

Las capturas de comprobante deben ocultar navegación y controles de impresión, usar fondo blanco y no mostrar datos personales reales.

## Evidencia API

Guardar método/ruta, estado HTTP, código público, forma de la respuesta y correlación. Redactar por completo:

- encabezados `Cookie`, `Set-Cookie` y `X-CSRF-Token`;
- cuerpos con contraseña o token de recuperación;
- datos de conexión;
- trazas internas.

Ejemplo **ilustrativo, no evidencia registrada**:

```text
POST /api/sales
HTTP 201
X-Correlation-Id: 7bd0…2f1c
Body: { "data": { "invoiceId": "42", "total": "112.00" } }
Cookie/CSRF: [REDACTADO]
```

## Evidencia SQL

Ejecutar verificaciones con una cuenta administrativa de pruebas y guardar consulta, conteos y filas mínimas necesarias. Incluir nombre de base de prueba y build de SQL Server. No exportar columnas secretas. Para concurrencia conservar marcas de tiempo y correlaciones de ambas sesiones.

La evidencia de rollback comprueba ausencia de todos los efectos y presencia del incidente separado; una excepción de la API por sí sola no demuestra rollback.

Los archivos bajo `database/tests/` no son evidencia por existir. La captura debe contener su salida completa, el código de retorno de `sqlcmd`, las variables no secretas utilizadas y la revisión exacta. `02_pool_identity_pa29.sql` cubre un caso de limpieza de contexto, no toda PA29; `03_save-transaction.sql` es didáctico; `04_sale-rollback-fault.sql` cubre un único punto posterior al encabezado y tampoco aprueba PA06 sin el resto del protocolo y el acta.

## Rendimiento

Conservar:

1. acta de equipo/configuración;
2. versión/semilla y conteos del dataset;
3. 20 calentamientos identificados y excluidos;
4. al menos 100 mediciones válidas por escenario;
5. datos crudos sin redondear;
6. script/comando exacto;
7. errores, rechazos funcionales, máximo y cálculo p95;
8. verificaciones de integridad posteriores.

## Integridad de archivos

Después de redactar, calcular SHA-256 con PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '<ruta-de-evidencia>'
```

Registrar el hash en el manifiesto. Si el archivo cambia, crear una nueva revisión y actualizar el manifiesto; no conservar un hash que ya no corresponde.

## Cambio de estado

Antes de modificar una fila de [Matriz PA01–PA32](test-matrix.md), compruebe:

1. que la revisión, entorno, datos y precondiciones coinciden con la corrida;
2. que todos los resultados esperados de la PA fueron observados, incluidos casos negativos y concurrencia real cuando se exigen;
3. que cada archivo existe, fue redactado y su SHA-256 coincide con el manifiesto;
4. que el resultado observado no se dedujo de código, mocks o una PA distinta;
5. que `Aprobada`, `Fallida` o `Bloqueada` incluye ejecutor y, cuando corresponda, incidencia o causa externa concreta.

Si falta cualquiera de estos elementos, el estado continúa **Pendiente**. Esta regla también impide declarar cumplimiento QC o aptitud productiva a partir de la documentación.
