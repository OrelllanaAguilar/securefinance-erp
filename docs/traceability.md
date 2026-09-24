# Trazabilidad funcional

Esta matriz enlaza la especificación funcional resumida con rutas React, operaciones HTTP y objetos SQL presentes en el código. Una relación indica cobertura estática de diseño/código; **no** significa que el recorrido funcione en runtime ni que una PA esté ejecutada. El estado oficial de todas las PA se conserva en [Matriz PA01–PA32](test-matrix.md).

La flecha de trazabilidad es direccional: la expectativa UC/PA conduce a la implementación y después a la evidencia. La existencia de implementación no reemplaza la expectativa, y una prueba unitaria con dobles de SQL no reemplaza una corrida contra SQL Server real.

## UC → pantalla → HTTP → SQL → PA

| UC | Caso y pantalla/ruta | Endpoint(s) | Procedimiento(s) / función SQL | PA principales |
|---|---|---|---|---|
| UC01 | Autenticación de usuario — `/acceso` | `POST /api/auth/login`; `GET /api/auth/session` | `sp_AutenticarUsuario`, `sp_ValidarSesionApi`, `sp_RegistrarAcceso`, `sp_ObtenerPermisosUsuario` | PA01, PA04, PA11, PA29 |
| UC02 | Cambio de contraseña segura e inicial obligatorio — `/perfil/seguridad` | `PUT /api/me/password` | `sp_CambiarPassword`, `fn_ContrasenaCumplePolitica` | PA02, PA11 |
| UC03 | Venta transaccional — `/ventas/nueva`, `/ventas`, `/ventas/:id` | `POST /api/sales/quote`; `POST /api/sales`; `GET /api/sales`; `GET /api/sales/result/:key`; `GET /api/sales/:id` | `sp_CotizarVenta`, `sp_ProcesarVentaTransaccional`, `sp_ConsultarVentasPropias`, `sp_ConsultarResultadoVenta`, `sp_ConsultarFactura`, `fn_CalcularSubtotal`, `fn_CalcularIVA`, `TVP_DetalleFactura` | PA05–PA10, PA22, PA25, PA28, PA30 |
| UC04 | Consulta de bitácoras y auditoría — `/auditoria` | `GET /api/audit/access`; `GET /api/audit/dml`; `GET /api/audit/ddl` | `sp_ConsultarBitacoraAcceso`, `sp_ConsultarAuditoriaDML`, `sp_ConsultarAuditoriaDDL`, `fn_ConsultarAuditoriaDML`; triggers DML y DDL | PA01, PA04, PA09, PA12, PA29 |
| UC05 | Recuperación/restablecimiento — `/recuperar`, `/restablecer` | `POST /api/auth/recover`; `POST /api/auth/reset` | `sp_SolicitarRecuperacion`, `sp_RestablecerPassword`, `fn_ContrasenaCumplePolitica` | PA03, PA11 |
| UC06 | Perfil y permisos propios — `/perfil` | `GET /api/me`; `GET /api/me/preferences` | `sp_ConsultarPerfil`, `sp_ObtenerPermisosUsuario`, `sp_ObtenerPreferenciasUsuario` | PA04, PA18, PA23, PA29 |
| UC07 | Roles y permisos — `/roles` | `GET/POST/PATCH /api/roles`; `GET /api/permissions` | `sp_ListarRoles`, `sp_CrearRol`, `sp_ActualizarRol`, `sp_ListarPermisos`, `fn_TienePermiso` | PA04, PA11, PA18, PA27 |
| UC08 | Productos, precios, estado e inventario — `/productos` | `GET/POST/PATCH /api/products`; `GET /api/products/options`; `POST /api/products/:id/inventory` | `sp_ListarProductos`, `sp_ListarUnidadesMedida`, `sp_CrearProducto`, `sp_ActualizarProducto`, `sp_AjustarInventario`; triggers DML | PA09, PA10, PA21, PA27, PA28 |
| UC09 | Clientes y estado — `/clientes` | `GET/POST/PATCH /api/customers` | `sp_ListarClientes`, `sp_CrearCliente`, `sp_ActualizarCliente`; triggers DML | PA10, PA21, PA27, PA28 |
| UC10 | Reportes de ventas — `/reportes/ventas`, detalle `/ventas/:id` | `GET /api/reports/sales`; `GET /api/sales/:id` | `sp_ObtenerHistoricoVentas`, `sp_ConsultarFactura`, `fn_ObtenerHistoricoVentas` | PA12, PA21, PA25, PA28, PA30 |
| UC11 | Administración de usuarios — `/usuarios` | `GET/POST/PATCH /api/users`; `POST /api/users/:id/reset-password` | `sp_ListarUsuarios`, `sp_CrearUsuario`, `sp_ActualizarUsuario`, `sp_GenerarPasswordTemporal` | PA11, PA18, PA21, PA27 |
| UC12 | Cierre, expiración y revocación — acción «Cerrar sesión» | `POST /api/auth/logout`; validación previa de todas las rutas protegidas | `sp_CerrarSesion`, `sp_ValidarSesionApi`, `sp_ResolverSesion` | PA11, PA23, PA29 |
| UC13 | Apariencia por navegador/cuenta — selectores de acceso, recuperación, restablecimiento, encabezado y `/perfil` | `GET/PUT /api/me/preferences` para cuenta; sin HTTP para preferencia anónima | `sp_ObtenerPreferenciasUsuario`, `sp_GuardarPreferenciasUsuario` | PA13–PA17, PA20, PA24 |
| UC14 | Inicio y navegación autorizada — `/inicio`, guardas y páginas de sistema | `GET /api/dashboard`; comprobación de sesión/permisos en cada endpoint | `sp_ObtenerResumenInicio`, `sp_ValidarSesionApi`, `sp_ResolverSesion`, `fn_TienePermiso` | PA18, PA19, PA23 |

`sp_ValidarTokenRecuperacion` forma parte del catálogo SQL interno, pero la API actual no lo invoca ni le concede `EXECUTE` a la cuenta HTTP; por eso no se presenta como eslabón del recorrido UC05.

## Trazabilidad operativa fuera de UC

| Operación | Entrada | SQL/artefacto | Alcance comprobable |
|---|---|---|---|
| Salud inmediata | `GET /api/health`; `pnpm sql:verify` | `sp_VerificarEstado`; `scripts/Test-Database.ps1` | Conectividad y permiso de ejecución del SP; no prueba salud integral ni QC. |
| Preparación local | `scripts/Install-Database.ps1` | `install.sql` → aprovisionamiento API → bootstrap → semilla opcional `_Test` | Secuencia implementada; PA32 exige ejecutarla en copia limpia y registrar evidencia. |
| Contrato SQL | ejecución administrativa de `database/tests/01_contract.sql` | catálogos `sys.*` y reglas puntuales | Inventario/firmas/reglas inspeccionadas por el script; no sustituye PA funcionales. |
| Aislamiento de contexto | `database/tests/02_pool_identity_pa29.sql` | `sp_ResolverSesion`, `SESSION_CONTEXT` | Caso SQL de limpieza ante sesión inválida; PA29 completo también exige alternar cuentas mediante el pool/API. |
| Mínimo privilegio real | `RUN_SQL_INTEGRATION=true`; `pnpm test:integration` | login SQL configurado en `.env`, `sp_VerificarEstado` y denegaciones directas | Comprueba un SP concedido y tres operaciones denegadas; no sustituye toda la matriz de permisos. |
| Humo funcional real | `pnpm test:smoke` sobre `_Test` | API integrada, SP y datos sintéticos | Cambio inicial, permisos, tema, inventario, cotización, venta/idempotencia secuencial, comprobante y reporte; cobertura parcial de varias PA. |
| Rollback posterior al encabezado | `database/tests/04_sale-rollback-fault.sql` | trigger temporal transaccional y `sp_ProcesarVentaTransaccional` | Comprueba ausencia de efectos parciales e incidente separado en un punto; PA06 exige acta completa. |
| Interfaz en navegador | `pnpm test:e2e`; `pnpm test:e2e:private` | Microsoft Edge, Axe, API/SQL real para el recorrido privado | Cobertura automatizada parcial de páginas, temas y viewports; teclado/zoom/estados restantes siguen manuales. |
| Respaldo/restauración | `database/operations/*.sql` y guía operativa | `BACKUP`, `VERIFYONLY`, `RESTORE` | Herramientas disponibles; PA31/QC07 requieren una restauración aislada medida y evidenciada. |

## Rutas privadas y permiso visible

| Ruta | Permiso de entrada | Alcance adicional en SQL/API |
|---|---|---|
| `/inicio` | sesión válida | El resumen global solo se entrega con `REPORTES_LEER`; accesos rápidos dependen de permisos. |
| `/ventas/nueva` | `VENTAS_CREAR` | Actor tomado de sesión; cliente/productos/stock/precios validados por SQL. |
| `/ventas` y `/ventas/:id` | `VENTAS_CREAR` o `REPORTES_LEER` | El primero limita a facturas propias; el segundo permite todas. |
| `/productos` | `VENTAS_CREAR` o `PRODUCTOS_GESTIONAR` | Solo `PRODUCTOS_GESTIONAR` muta catálogo/inventario. |
| `/clientes` | `VENTAS_CREAR` o `CLIENTES_GESTIONAR` | Solo `CLIENTES_GESTIONAR` muta catálogo. |
| `/reportes/ventas` | `REPORTES_LEER` | Rango máximo de 366 días y totales del filtro completo. |
| `/auditoria` | `AUDITORIA_LEER` | La cuenta API solo consulta bitácoras mediante SP. |
| `/usuarios` | `USUARIOS_GESTIONAR` | Protege último administrador y revoca seguridad al cambiar estado/roles. |
| `/roles` | `ROLES_GESTIONAR` | Protege rol administrador y revoca sesiones afectadas al cambiar permisos. |
| `/perfil` | sesión válida | Solo identidad, roles, permisos y preferencia de la sesión. |
| `/perfil/seguridad` | sesión válida, incluso cambio obligatorio | Tras cambiar contraseña se termina la sesión. |

## Cobertura PA transversal

Estas PA atraviesan más de un UC y deben enlazarse a evidencias por operación, no adjudicarse a una sola pantalla.

| PA | Cobertura transversal |
|---|---|
| PA20 | Formularios interactivos UC01–UC12; validación, conservación no sensible, navegación con cambios y cambio de tema. |
| PA21 | Listados de facturas, productos, clientes, reportes, auditoría, usuarios y roles; filtros, paginación, orden y estados. |
| PA24 | Todos los UC visibles: teclado, foco, etiquetas, contraste, 200 %, 320/768/1280 y ambos temas. |
| PA26 | Todos los módulos: runtime sin Internet y fallos diferenciados de API/BD. |
| PA27 | Límites, cuerpos estrictos, `rowversion` y concurrencia en catálogos/seguridad. |
| PA29 | Autenticación/autorización/auditoría en conexiones reutilizadas; identidad siempre desde la sesión. |
| PA30 | Venta y reportes bajo QC01/QC02 con dataset y equipo registrados. |
| PA31 | Continuidad de todos los datos persistentes mediante respaldo/restauración. |
| PA32 | Instalación, compilación, reinicio, persistencia y operación offline. |

## Trazabilidad de integridad de venta

```mermaid
flowchart LR
    UC03[UC03 Venta] --> UI[/ventas/nueva]
    UI --> Q[POST /api/sales/quote]
    UI --> S[POST /api/sales]
    S --> TVP[dbo.TVP_DetalleFactura]
    S --> SP[sp_ProcesarVentaTransaccional]
    SP --> F[(Factura)]
    SP --> D[(Detalle_Factura)]
    SP --> P[(Producto/stock)]
    SP --> C[(MovimientoCaja)]
    SP --> A[(Auditoría DML)]
    SP --> R[sp_ConsultarResultadoVenta]
    F --> PAs[PA05 PA06 PA07 PA08 PA10 PA22 PA28]
```

## Regla de mantenimiento

Cuando cambie una ruta, SP o permiso, se actualizan en la misma revisión:

1. este mapa;
2. [Contratos API](api-contracts.md);
3. [Catálogo SQL](stored-procedures.md);
4. la PA afectada sin alterar su resultado observado previo; si el contrato cambió, se programa una nueva corrida.

También se actualiza el conteo de inventario del [README de documentación](README.md#inventario-estático-contrastado). Si falta un arnés necesario, se conserva la PA en **Pendiente** y se registra el hueco; no se infiere `Aprobada` ni `Bloqueada` sin una corrida y causa documentadas.
