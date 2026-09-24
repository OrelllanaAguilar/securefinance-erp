# Contratos de la API HTTP

## Convenciones generales

- Base relativa: `/api`; mismo origen que la SPA en ejecución integrada.
- Medios: solicitudes y respuestas JSON UTF-8, salvo `204 No Content`.
- El analizador acepta JSON estricto y limita el cuerpo a 256 KiB. Los esquemas rechazan propiedades no declaradas.
- La cookie de sesión es opaca, `HttpOnly`, `SameSite=Strict`, `Path=/` y `Secure` cuando se configura HTTPS. El cliente usa `credentials: include`.
- Toda respuesta incluye `X-Correlation-Id`. Se conserva un UUID v4 válido enviado por el cliente; en otro caso la API genera uno.
- Cada escritura autenticada exige `X-CSRF-Token`, obtenido en el acceso o en `GET /api/auth/session`. Los métodos no seguros también se limitan a los orígenes configurados.
- Fechas de filtro usan `YYYY-MM-DD`; instantes de respuesta usan ISO 8601 UTC. Los importes se transportan como cadenas con exactamente dos decimales.
- `page` empieza en 1 y `pageSize` solo admite `10`, `25` o `50`; el valor predeterminado es 25.

### Envolventes

Éxito individual:

```json
{
  "data": { "id": 42 }
}
```

Listado:

```json
{
  "data": [],
  "meta": {
    "page": 1,
    "pageSize": 25,
    "total": 0,
    "totalPages": 0
  }
}
```

Error público:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Revise los datos enviados.",
    "fields": { "lines.0.quantity": "Valor no válido" }
  },
  "correlationId": "00000000-0000-4000-8000-000000000000"
}
```

`fields` solo aparece en errores de validación que pueden asociarse con campos. No se devuelven mensajes SQL, trazas, cookies, hashes ni tokens privados.

### Autorización

| Código | Alcance |
|---|---|
| `VENTAS_CREAR` | Cotizar/procesar ventas, consultar facturas propias y catálogos activos. |
| `REPORTES_LEER` | Reporte, métricas y todas las facturas. |
| `PRODUCTOS_GESTIONAR` | Crear/editar productos y ajustar inventario. |
| `CLIENTES_GESTIONAR` | Crear/editar clientes. |
| `AUDITORIA_LEER` | Accesos, DML y DDL. |
| `USUARIOS_GESTIONAR` | Usuarios, roles asignados y credencial temporal. |
| `ROLES_GESTIONAR` | Roles y permisos. |

La UI usa esta matriz para navegar, pero cada endpoint y cada SP vuelven a comprobarla. Una sesión marcada `mustChangePassword` solo puede consultar su sesión, cambiar contraseña y cerrar sesión.

## Autenticación y sesión

| Método y ruta | Acceso / protección | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `POST /api/auth/login` | Público; límite 60/15 min en HTTP más regla SQL | `{username, password}`; usuario ASCII 3–50, contraseña 1–128 | `200`; usuario, permisos, roles, vencimientos, `csrfToken` y configuración regional; fija cookie | `sp_AutenticarUsuario` |
| `GET /api/auth/session` | Sesión; no renueva inactividad; permite cambio obligatorio | — | `200`; misma forma de sesión y nuevo `csrfToken` | `sp_ValidarSesionApi` |
| `POST /api/auth/logout` | Sesión + CSRF; permite cambio obligatorio | cuerpo omitido | `204`; revoca sesión y borra cookie aun si falla el cierre SQL | `sp_CerrarSesion` |
| `POST /api/auth/recover` | Público; límite HTTP | `{identity}` de 3–254 | `202`; mensaje idéntico exista o no la cuenta | `sp_SolicitarRecuperacion` |
| `POST /api/auth/reset` | Público; límite HTTP | `{token, newPassword}`; token 32–256; política 12–128 | `200`; mensaje de restablecimiento | `sp_RestablecerPassword` |

El enlace de recuperación se escribe únicamente en el buzón privado configurado, fuera de `dist`; el token en claro no forma parte de la respuesta HTTP.

## Cuenta y preferencias

| Método y ruta | Acceso / protección | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `GET /api/me` | Sesión | — | `200`; perfil, `permissions[]` y `roles[]` | `sp_ConsultarPerfil` |
| `GET /api/me/preferences` | Sesión; no renueva inactividad | — | `200`; `{theme}` | `sp_ObtenerPreferenciasUsuario` |
| `PUT /api/me/preferences` | Sesión + CSRF | `{theme}`: `claro`, `oscuro` o `sistema` | `200`; preferencia persistida | `sp_GuardarPreferenciasUsuario` |
| `PUT /api/me/password` | Sesión + CSRF; permite cambio obligatorio | `{currentPassword, newPassword}` | `200`; revoca sesiones/tokens y borra cookie | `sp_CambiarPassword` |

La contraseña nueva conserva los caracteres recibidos; no se recorta. Debe tener 12–128 caracteres, mayúscula, minúscula, número y símbolo.

## Inicio

| Método y ruta | Acceso | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `GET /api/dashboard` | Sesión | — | `200`; `summary`, `shortcuts[]`, `refreshedAt` | `sp_ObtenerResumenInicio` |

El resumen global solo debe contener datos cuando el actor posee `REPORTES_LEER`; los accesos directos proceden de permisos efectivos.

## Productos e inventario

Parámetros comunes de lista: `page`, `pageSize`, `search` (≤160), `status=all|active|inactive`, `sort=code|description|price|stock|updatedAt`, `direction=asc|desc`.

| Método y ruta | Permiso / protección | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `GET /api/products` | `VENTAS_CREAR` o `PRODUCTOS_GESTIONAR` | consulta común | `200` listado paginado | `sp_ListarProductos` |
| `GET /api/products/options` | igual | — | `200` unidades activas | `sp_ListarUnidadesMedida` |
| `POST /api/products` | `PRODUCTOS_GESTIONAR` + CSRF | `{code, description, unit, price}` | `201` producto; stock inicial 0 | `sp_CrearProducto` |
| `PATCH /api/products/:id` | `PRODUCTOS_GESTIONAR` + CSRF | subconjunto de `{code, description, unit, price, active}` y `version` obligatoria | `200` producto actualizado | `sp_ActualizarProducto` |
| `POST /api/products/:id/inventory` | `PRODUCTOS_GESTIONAR` + CSRF | `{delta, reason, version}`; entero no cero, motivo 10–250, `version=0x` + 16 hex | `200` stock/versión nuevos | `sp_AjustarInventario` |

Límites autoritativos: código 1–30, descripción 2–160, precio `0.01–999999.99`, unidad de catálogo y stock no negativo. Una versión obsoleta devuelve `409 STALE_VERSION`.

## Clientes

Lista: `page`, `pageSize`, `search` (≤160), `status=all|active|inactive`, `sort=identifier|name|email|updatedAt`, `direction=asc|desc`.

| Método y ruta | Permiso / protección | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `GET /api/customers` | `VENTAS_CREAR` o `CLIENTES_GESTIONAR` | consulta de lista | `200` listado paginado | `sp_ListarClientes` |
| `POST /api/customers` | `CLIENTES_GESTIONAR` + CSRF | `{identifier, name, email?, phone?}` | `201` cliente | `sp_CrearCliente` |
| `PATCH /api/customers/:id` | `CLIENTES_GESTIONAR` + CSRF | subconjunto de `{identifier, name, email, phone, active}` y `version` | `200` cliente actualizado | `sp_ActualizarCliente` |

`identifier` admite 1–30, `name` 2–120, correo hasta 254 y teléfono hasta 30. Cadena vacía o `null` elimina los contactos opcionales; no borra facturas históricas.

## Ventas y comprobantes

Una línea siempre tiene `{productId: entero positivo, quantity: 1..9999}`. Debe haber 1–100 productos distintos; no se aceptan precios enviados por el cliente.

| Método y ruta | Permiso / protección | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `POST /api/sales/quote` | `VENTAS_CREAR` + CSRF | `{customerId, lines[]}` | `200`; líneas valoradas y totales SQL | `sp_CotizarVenta` |
| `POST /api/sales` | `VENTAS_CREAR` + CSRF | `{customerId, lines[], acceptedTotal, idempotencyKey}` | `201` nueva; `200` reintento idéntico; factura resumida | `sp_ProcesarVentaTransaccional` |
| `GET /api/sales` | `VENTAS_CREAR` o `REPORTES_LEER` | lista + `from?`, `to?`, `scope=mine|all`, `sort=date|number|customer|total` | `200` facturas autorizadas | `sp_ConsultarVentasPropias` |
| `GET /api/sales/result/:key` | `VENTAS_CREAR` | UUID de la clave | `200` si resuelta; `202` `{status:"pending", idempotencyKey}` si aún no aparece | `sp_ConsultarResultadoVenta` |
| `GET /api/sales/:id` | `VENTAS_CREAR` o `REPORTES_LEER` | id positivo | `200`; encabezado, `lines[]`, `cashMovement` | `sp_ConsultarFactura` |

`acceptedTotal` usa cadena decimal exacta. Si ocurre un fallo técnico después de enviar la venta, `POST /api/sales` devuelve `503 SALE_RESULT_UNKNOWN`: el cliente conserva la misma clave y usa el endpoint `result`; no crea otra clave mientras el resultado sea incierto. Una clave ya usada con contenido diferente devuelve `409 IDEMPOTENCY_CONFLICT`.

Un actor con `VENTAS_CREAR` solo puede consultar sus facturas. `scope=all` y acceso a facturas ajenas requieren `REPORTES_LEER`, incluso si el navegador altera la consulta.

## Reportes y auditoría

| Método y ruta | Permiso | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `GET /api/reports/sales` | `REPORTES_LEER` | `from`, `to`, paginación, búsqueda, `sort=date|number|customer|cashier|total`, dirección | `200`; listado, `meta.totals`, `meta.range` | `sp_ObtenerHistoricoVentas` |
| `GET /api/audit/access` | `AUDITORIA_LEER` | paginación, búsqueda, fechas opcionales, orden | `200` bitácora de acceso | `sp_ConsultarBitacoraAcceso` |
| `GET /api/audit/dml` | `AUDITORIA_LEER` | igual | `200` cambios DML | `sp_ConsultarAuditoriaDML` |
| `GET /api/audit/ddl` | `AUDITORIA_LEER` | igual | `200` cambios de esquema | `sp_ConsultarAuditoriaDDL` |

El rango de reporte contiene entre 1 y 366 días inclusivos (`to - from` de 0 a 365). Los totales corresponden al filtro completo, no solo a la página. Las categorías de auditoría son cerradas; cualquier otra categoría falla con `400`.

## Usuarios, roles y permisos

Las listas aceptan paginación, búsqueda, `sort=name|username|status|updatedAt` y dirección. Las mutaciones requieren CSRF y `version` en actualizaciones.

| Método y ruta | Permiso | Entrada | Éxito | Procedimiento |
|---|---|---|---|---|
| `GET /api/users` | `USUARIOS_GESTIONAR` | consulta de lista | `200` usuarios y roles | `sp_ListarUsuarios` |
| `POST /api/users` | `USUARIOS_GESTIONAR` | `{username, displayName, email?, roleIds[]}` | `201`; usuario y contraseña temporal mostrada una vez | `sp_CrearUsuario` |
| `PATCH /api/users/:id` | `USUARIOS_GESTIONAR` | subconjunto de `{displayName, email, active, roleIds}` + `version` | `200`; usuario; revoca sesiones si cambia seguridad | `sp_ActualizarUsuario` |
| `POST /api/users/:id/reset-password` | `USUARIOS_GESTIONAR` | `{}` exacto | `200`; contraseña temporal mostrada una vez | `sp_GenerarPasswordTemporal` |
| `GET /api/roles` | `ROLES_GESTIONAR` | consulta de lista | `200` roles y permisos | `sp_ListarRoles` |
| `POST /api/roles` | `ROLES_GESTIONAR` | `{name, description?, permissions[]}` | `201` rol | `sp_CrearRol` |
| `PATCH /api/roles/:id` | `ROLES_GESTIONAR` | subconjunto de `{name, description, active, permissions}` + `version` | `200`; revoca sesiones afectadas al cambiar permisos | `sp_ActualizarRol` |
| `GET /api/permissions` | `ROLES_GESTIONAR` | — | `200` catálogo activo | `sp_ListarPermisos` |

`username` es ASCII 3–50; `displayName` 2–120; `roleIds` admite hasta 30 IDs. El nombre de rol mide 3–60 y la descripción HTTP hasta 200. La API genera la credencial temporal, la envía como parámetro tipado y solo la muestra en esa respuesta; debe entregarse por canal privado.

## Estado de servicio

| Método y ruta | Acceso | Éxito | Procedimiento |
|---|---|---|---|
| `GET /api/health` | Público local | `200`; `{status, database, checkedAt}` | `sp_VerificarEstado` |

Este endpoint demuestra conectividad inmediata, no salud integral ni cumplimiento de QC.

## Estados y códigos de error

| HTTP | Código público frecuente | Uso |
|---:|---|---|
| 400 | `INVALID_JSON`, `VALIDATION_ERROR`, `INVALID_CREDENTIALS`, `RESET_INVALID` | JSON/esquema/regla inválida; credenciales y recuperación no revelan detalles internos. |
| 401 | `SESSION_REQUIRED`, `SESSION_INVALID` | Sin cookie, sesión cerrada, vencida o revocada; la API borra la cookie. |
| 403 | `CSRF_INVALID`, `ORIGIN_INVALID`, `FORBIDDEN`, `PASSWORD_CHANGE_REQUIRED` | Origen/CSRF/permiso o restricción por cambio inicial. |
| 404 | `NOT_FOUND`, `ROUTE_NOT_FOUND` | Recurso o ruta inexistente. |
| 409 | `CONFLICT`, `STALE_VERSION`, `IDEMPOTENCY_CONFLICT`, `INSUFFICIENT_STOCK` | Conflicto de negocio o concurrencia. |
| 429 | `RATE_LIMITED` | Demasiados intentos o solicitudes. |
| 503 | `DATABASE_UNAVAILABLE`, `SALE_RESULT_UNKNOWN` | Base no disponible o resultado de venta aún no determinable. |
| 500 | `INTERNAL_ERROR` | Error no clasificado; mensaje sanitizado. |

Los números SQL `51001–51012` se convierten a estos códigos. Los estados descritos son contratos de diseño inspeccionados; sus pruebas PA permanecen **Pendiente** hasta ejecución real.
