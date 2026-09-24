# Catálogo SQL

## Instalación y convenciones

`database/install.sql` es el punto de entrada SQLCMD para **objetos de base**. Ejecuta, en orden, base/configuración, esquema, funciones, seguridad, catálogos, ventas/reportes, auditoría y permisos. `$(DatabaseName)` debe ser un identificador simple autorizado. No crea por sí solo el login SQL ni la cuenta bootstrap.

El punto de entrada recomendado para preparar un entorno local completo es `scripts/Install-Database.ps1`. Después de `install.sql`, ejecuta `provision-api-login.sql`, `provision-bootstrap-admin.sql` y, si se solicita para una base `_Test`, `seed-demo.sql`; finalmente genera la configuración local y la credencial inicial privada. La secuencia y los requisitos se detallan en [README de documentación](README.md#instalación-local-reproducible).

Los scripts pertenecen al canal administrativo; la API no instala, migra ni siembra objetos al arrancar. Reejecutar la línea base crea objetos ausentes y recompila código con `CREATE OR ALTER`, pero no constituye por sí mismo una migración completa de tablas preexistentes.

### Inventario de la línea base

| Clase | Declarados | Expuestos a la cuenta API |
|---|---:|---:|
| Procedimientos | 41 | 36 mediante `GRANT EXECUTE` individual |
| Funciones | 6 | 0 directas; se consumen dentro de SP |
| Tipos de tabla | 4 | 3 (`TVP_DetalleFactura`, `TVP_ListaEnteros`, `TVP_CodigosPermiso`) |
| Triggers | 11 | 0 directos; 10 DML y 1 DDL de base |

Los cinco SP internos sin concesión a `SecureFinanceApiExecutor` son `sp_LimpiarContextoAuditoria`, `sp_RegistrarAcceso`, `sp_ResolverSesion`, `sp_ObtenerPermisosUsuario` y `sp_ValidarTokenRecuperacion`.

Abreviaturas usadas en las tablas:

- **S**: `@SesionHash varbinary(64)`, `@DireccionIP varchar(45)=NULL`, `@CorrelationId uniqueidentifier=NULL`.
- **P**: `@Pagina int=1`, `@TamanoPagina tinyint=25`, `@Busqueda nvarchar(160)=NULL`, más orden/dirección del módulo.
- **Lista**: primer recordset de filas; segundo recordset `{page,pageSize,total,totalPages}`.
- Todos los procedimientos protegidos resuelven otra vez la sesión en SQL. Los permisos indicados son mínimos funcionales, no sustituyen los `GRANT` de la cuenta API.
- Los procedimientos de escritura usan parámetros tipados y devuelven errores `51001–51012` para que la API los transforme en errores públicos.

## Tipos definidos por el usuario

| Tipo | Columnas | Uso |
|---|---|---|
| `dbo.TVP_DetalleFactura` | `ProductoId int PK`, `Cantidad int CHECK 1..9999` | Cotización y venta; una fila por producto, máximo funcional 100. |
| `dbo.TVP_IdEntero` | `Id int PK` | Lista genérica de IDs; reservado por el esquema. |
| `dbo.TVP_ListaEnteros` | `Id int PK` | Roles asignados a un usuario. |
| `dbo.TVP_CodigosPermiso` | `Codigo varchar(50) PK` | Permisos asignados a un rol. |

La API necesita `EXECUTE` y `REFERENCES` sobre cada tipo que envía. El rol real de base es `SecureFinanceApiExecutor`; para ventas, el requisito explícito es:

```sql
GRANT EXECUTE ON TYPE::dbo.TVP_DetalleFactura TO SecureFinanceApiExecutor;
GRANT REFERENCES ON TYPE::dbo.TVP_DetalleFactura TO SecureFinanceApiExecutor;
```

`07_permissions.sql` aplica ambas concesiones también a `TVP_ListaEnteros` y `TVP_CodigosPermiso`, porque la API los materializa para usuarios/roles. No se concede acceso genérico a todos los tipos.

## Funciones

| Función | Parámetros / retorno | Responsabilidad |
|---|---|---|
| `fn_CalcularSubtotal` | `(@Cantidad int, @Precio decimal(19,2)) → decimal(19,2)` | Multiplica y redondea a dos decimales; usada por cotización/venta. |
| `fn_CalcularIVA` | `(@Subtotal decimal(19,2)) → decimal(19,2)` | Lee `ConfiguracionSistema.TasaIVA` y redondea una vez el IVA de encabezado. |
| `fn_ContrasenaCumplePolitica` | `(@Contrasena nvarchar(128)) → bit` | Exige 12–128, mayúscula, minúscula, número y símbolo sin recorte. |
| `fn_TienePermiso` | `(@UsuarioId int, @Codigo varchar(60)) → bit` | Resuelve permisos mediante roles/permisos activos. |
| `fn_ObtenerHistoricoVentas` | `(@FechaDesdeUtc datetime2(3), @FechaHastaExclusivaUtc datetime2(3)) → tabla` | Solo facturas `Confirmada` en intervalo UTC semiabierto. |
| `fn_ConsultarAuditoriaDML` | fechas UTC opcionales + búsqueda → tabla | Filtra la bitácora DML; la API la consume indirectamente mediante SP. |

Las funciones tabulares no se exponen directamente a la cuenta HTTP; los procedimientos aplican permiso, zona horaria, paginación y proyección pública.

## Seguridad, sesión y preferencias

| Procedimiento | Parámetros propios además de S | Permiso / consumidor | Resultado y efecto |
|---|---|---|---|
| `sp_LimpiarContextoAuditoria` | ninguno | Interno | Limpia `UsuarioId`, usuario, IP, correlación y motivo de `SESSION_CONTEXT` en la conexión reutilizable. |
| `sp_RegistrarAcceso` | usuario intentado/id, resultado, motivo, IP, agente, correlación | Interno | Inserta `Bitacora_Acceso`; nunca recibe contraseña/hash/salt/token. |
| `sp_ResolverSesion` | permiso opcional, permitir cambio obligatorio, actualizar actividad; tres `OUTPUT` | Interno, base de todos los SP protegidos | Valida sesión/cuenta/versiones/vencimientos/permiso, establece contexto y devuelve identidad. |
| `sp_ObtenerPermisosUsuario` | `@UsuarioId` | Interno | Permisos y roles activos del usuario resuelto. |
| `sp_AutenticarUsuario` | usuario, contraseña, hash de nueva sesión, agente, 30 min/8 h | Público desde login | Valida límite/estado/hash académico, registra acceso, crea sesión y devuelve usuario + permisos + roles. |
| `sp_ValidarSesionApi` | S + `@ActualizarActividad bit` | Middleware | Usuario/sesión + permisos + roles; opcionalmente renueva inactividad sin superar vencimiento absoluto. |
| `sp_CerrarSesion` | S | Cuenta propia | Marca la sesión revocada. |
| `sp_ConsultarPerfil` | S | Cuenta propia | Perfil; segundo recordset permisos; tercero roles. |
| `sp_ObtenerPreferenciasUsuario` | S | Cuenta propia | Tema vigente; lectura sin confiar en ID del cliente. |
| `sp_GuardarPreferenciasUsuario` | `@Tema varchar(10)` | Cuenta propia | `MERGE`/actualiza `claro|oscuro|sistema`; devuelve tema y fecha. |
| `sp_CambiarPassword` | contraseña actual/nueva | Cuenta propia; permitido durante cambio obligatorio | Salt/hash nuevos, incrementa versión, revoca sesiones y tokens; obliga a iniciar de nuevo. |
| `sp_SolicitarRecuperacion` | identidad, hash del token, vigencia, IP/correlación | Público | Devuelve destino/vencimiento únicamente a la API cuando la cuenta es elegible; la API siempre emite la misma respuesta HTTP y escribe el enlace solo en el buzón privado. |
| `sp_ValidarTokenRecuperacion` | hash del token | Interno, sin `GRANT` ni llamada desde la API actual | Indica token vigente sin devolver el secreto; queda disponible para diagnóstico administrativo controlado. |
| `sp_RestablecerPassword` | hash del token, contraseña nueva, IP/correlación | Público con token | Consume atómicamente una vez, cambia salt/hash y revoca sesiones/tokens. |

`sp_ResolverSesion` siempre se acompaña de `sp_LimpiarContextoAuditoria` en éxito y error. PA29 debe comprobar que una conexión del pool usada por otra cuenta no conserva actor residual.

## Estado del servicio

| Procedimiento | Parámetros | Consumidor | Resultado |
|---|---|---|---|
| `sp_VerificarEstado` | ninguno | `GET /api/health` | Una fila con estado de base, UTC de SQL, moneda y zona IANA. No requiere sesión y no expone configuración secreta. |

## Usuarios, roles y permisos

| Procedimiento | Parámetros propios además de S | Permiso | Resultado / reglas |
|---|---|---|---|
| `sp_ListarPermisos` | — | `ROLES_GESTIONAR` | Catálogo activo ordenado por módulo/código. |
| `sp_ListarUsuarios` | P | `USUARIOS_GESTIONAR` | Lista usuarios y roles JSON; incluye estado, cambio obligatorio y `rowversion`. |
| `sp_CrearUsuario` | usuario, nombre visible, correo, contraseña temporal, `TVP_ListaEnteros` | `USUARIOS_GESTIONAR` | Crea cuenta, roles y preferencia `sistema`; hash/salt se generan en SQL. |
| `sp_ActualizarUsuario` | id, campos opcionales, flags de cambio, roles TVP, versión | `USUARIOS_GESTIONAR` | Control optimista, protege último administrador y revoca sesiones al cambiar estado/roles. |
| `sp_GenerarPasswordTemporal` | usuario id, contraseña temporal | `USUARIOS_GESTIONAR` | Salt/hash nuevos, cambio obligatorio; revoca sesiones/tokens. |
| `sp_ListarRoles` | P | `ROLES_GESTIONAR` | Lista roles y permisos JSON con `rowversion`. |
| `sp_CrearRol` | nombre, descripción, `TVP_CodigosPermiso` | `ROLES_GESTIONAR` | Crea rol y asignaciones validadas. |
| `sp_ActualizarRol` | id, campos/flags opcionales, permisos TVP, versión | `ROLES_GESTIONAR` | Control optimista; protege rol administrador; al cambiar permisos incrementa versión de seguridad y revoca sesiones afectadas. |

## Catálogos

| Procedimiento | Parámetros propios además de S | Permiso | Resultado / reglas |
|---|---|---|---|
| `sp_ListarUnidadesMedida` | — | `VENTAS_CREAR` o `PRODUCTOS_GESTIONAR` | Unidades activas. |
| `sp_ListarProductos` | P + estado | venta o gestión de productos | Lista con precio como texto, stock, estado, fecha y versión. |
| `sp_CrearProducto` | código, descripción, unidad, precio texto | `PRODUCTOS_GESTIONAR` | Valida catálogo/rango, crea con stock 0; código único. |
| `sp_ActualizarProducto` | id, campos opcionales, versión | `PRODUCTOS_GESTIONAR` | Actualización con `rowversion`; no cambia stock. |
| `sp_AjustarInventario` | producto, variación, motivo, versión | `PRODUCTOS_GESTIONAR` | Bloqueo transaccional, stock en rango, `MovimientoInventario` y motivo en auditoría. |
| `sp_ListarClientes` | P + estado | venta o gestión de clientes | Lista con contacto, estado y versión. |
| `sp_CrearCliente` | identificador, nombre, correo, teléfono | `CLIENTES_GESTIONAR` | Crea cliente; identificador único. |
| `sp_ActualizarCliente` | id, campos/flags opcionales, versión | `CLIENTES_GESTIONAR` | Actualización optimista; cadena vacía puede limpiar contacto. |

Todos los listados validan página `>0`, tamaños `10/25/50`, valores cerrados de orden/estado y desempate por PK.

## Ventas, comprobantes, reporte e inicio

| Procedimiento | Parámetros propios además de S | Permiso | Recordsets / garantías |
|---|---|---|---|
| `sp_CotizarVenta` | cliente, `TVP_DetalleFactura` | `VENTAS_CREAR` | 1: líneas con precio/stock; 2: subtotal, tasa, IVA, total y moneda. Precios/IVA se leen de SQL. |
| `sp_ProcesarVentaTransaccional` | cliente, detalle TVP, total aceptado texto, UUID | `VENTAS_CREAR` | Una fila de factura; `replayed` distingue alta/reintento. Serializa clave por usuario, bloquea productos en orden, recalcula, descuenta stock y crea factura/detalle/caja en una transacción. |
| `sp_ConsultarResultadoVenta` | UUID | `VENTAS_CREAR` | Factura de esa clave y usuario o cero filas si aún no está resuelta. |
| `sp_ConsultarVentasPropias` | P, fechas opcionales, alcance `mine|all` | venta propia; `all` requiere reportes | Lista y metadatos; fechas locales convertidas a intervalo UTC. |
| `sp_ConsultarFactura` | factura id | dueño con `VENTAS_CREAR` o `REPORTES_LEER` | 1: encabezado histórico; 2: líneas; 3: movimiento de caja. Fuera de alcance responde como no encontrado. |
| `sp_ObtenerHistoricoVentas` | fechas obligatorias + P | `REPORTES_LEER` | 1: ventas; 2: metadatos; 3: totales de todo el filtro. Máximo 366 días. |
| `sp_ObtenerResumenInicio` | — | sesión | 1: resumen diario solo con reportes; 2: accesos rápidos por permiso. |

### Atomicidad e idempotencia de `sp_ProcesarVentaTransaccional`

1. valida 1–100 filas y total textual exacto;
2. deriva actor de la sesión;
3. calcula huella SHA-256 canónica de cliente, total y detalle ordenado;
4. abre transacción y toma `sp_getapplock` exclusivo por usuario+UUID;
5. si existe la clave: misma huella devuelve la factura; huella distinta lanza `51008`;
6. bloquea cliente/configuración y productos en orden de `ProductoId`;
7. recalcula subtotal/IVA/total y comprueba stock/total aceptado;
8. descuenta stock e inserta encabezado, líneas y movimiento de caja;
9. confirma todo o revierte todo con `XACT_ABORT`/`TRY…CATCH`;
10. tras rollback, registra `Bitacora_Incidente` solo para fallos técnicos no funcionales y limpia el contexto.

La secuencia de factura puede dejar huecos por rollback; la integridad se evalúa por filas persistidas, no por continuidad numérica.

## Auditoría

| Procedimiento | Parámetros propios además de S | Permiso | Resultado |
|---|---|---|---|
| `sp_ConsultarBitacoraAcceso` | P + fechas opcionales | `AUDITORIA_LEER` | Intento/actor, resultado, motivo interno, IP, principal SQL, host/app y correlación. |
| `sp_ConsultarAuditoriaDML` | P + fechas opcionales | `AUDITORIA_LEER` | Actor, objeto, operación, registro, contexto, motivo e imágenes JSON. |
| `sp_ConsultarAuditoriaDDL` | P + fechas opcionales | `AUDITORIA_LEER` | Evento, objeto, esquema, principal, contexto y correlación. `commandText` se conserva como campo compatible y actualmente es `null`. |

Las fechas ingresadas son días locales y los SP las convierten a UTC semiabierto. La API proyecta solo estos SP; no concede `SELECT` directo sobre bitácoras.

## Triggers

| Trigger | Ámbito | Datos registrados |
|---|---|---|
| `trg_Usuario_AuditoriaDML` | `Usuario` I/U/D | Identidad visible, correo, cambio obligatorio, estado y versión de seguridad; excluye hash/salt. |
| `trg_Rol_AuditoriaDML` | `Rol` I/U/D | Nombre, descripción, indicador administrador y estado. |
| `trg_UsuarioRol_AuditoriaDML` | `Usuario_Rol` I/U/D | Par usuario/rol. |
| `trg_RolPermiso_AuditoriaDML` | `Rol_Permiso` I/U/D | Par rol/permiso. |
| `trg_Producto_AuditoriaDML` | `Producto` I/U/D | Catálogo, precio, stock y estado. |
| `trg_Cliente_AuditoriaDML` | `Cliente` I/U/D | Identificación, nombre, contacto y estado. |
| `trg_Factura_AuditoriaDML` | `Factura` I/U/D | Identidades referenciadas, moneda/tasa e importes; excluye clave/huella. |
| `trg_DetalleFactura_AuditoriaDML` | `Detalle_Factura` I/U/D | Factura/producto, cantidad, precio e importe. |
| `trg_MovimientoCaja_AuditoriaDML` | `MovimientoCaja` I/U/D | Factura, tipo, importe, moneda y usuario. |
| `trg_PreferenciaUsuario_AuditoriaDML` | `PreferenciaUsuario` I/U/D | Usuario y tema. |
| `trg_SecureFinance_AuditoriaDDL` | base, eventos DDL | Metadatos seguros de `EVENTDATA` (sin `TSQLCommand`), objeto, principal SQL y actor/contexto; guarda `Comando = NULL` y evita autorregistrar su propia bitácora/trigger. |

Los triggers DML son por conjuntos: unen `inserted` y `deleted` por PK y generan una fila de bitácora por registro afectado. Al ser parte de la transacción, un rollback también revierte su auditoría DML. PA09 verifica ambas propiedades.

## Errores de dominio

| SQL | Significado | HTTP esperado |
|---:|---|---:|
| 51001 | sesión inválida/vencida/revocada | 401 |
| 51002 | permiso insuficiente | 403 |
| 51003 | recurso no encontrado/fuera de alcance | 404 |
| 51004 | conflicto de negocio | 409 |
| 51005 | límite de intentos | 429 |
| 51006 | dato/filtro/configuración inválida | 400 |
| 51007 | cambio de contraseña obligatorio | 403 |
| 51008 | clave idempotente usada con otra huella | 409 |
| 51009 | `rowversion` obsoleta | 409 |
| 51010 | stock insuficiente/fuera de rango | 409 |
| 51011 | credenciales inválidas | 400 genérico |
| 51012 | token de recuperación inválido/vencido/usado | 400 genérico |

## Rol SQL y aprovisionamiento

`07_permissions.sql` crea `SecureFinanceApiExecutor` y aplica mínimo privilegio:

- `DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo`;
- `DENY ALTER, TAKE OWNERSHIP ON SCHEMA::dbo` y `REVOKE CONTROL ON SCHEMA::dbo`;
- `GRANT EXECUTE` solo a los procedimientos públicos consumidos por la API, incluido `sp_VerificarEstado`;
- no concede ejecución directa a los cinco SP internos inventariados arriba ni a funciones;
- `GRANT EXECUTE` y `GRANT REFERENCES` sobre los tres TVP enviados por `mssql`;
- ninguna pertenencia a `db_owner`, `db_datareader`, `db_datawriter` o roles de servidor elevados.

`provision-api-login.sql` se ejecuta por separado en modo SQLCMD con `DatabaseName`, `ApiLoginName` y una contraseña privada de al menos 16 caracteres. Crea el login/usuario si no existe y lo agrega a `SecureFinanceApiExecutor`; no elimina privilegios que una identidad preexistente pudiera tener, por lo que debe usarse un login dedicado y auditarse antes de operar. La contraseña no se guarda en el repositorio ni en evidencia.

`SchemaMigration` registra `0001_baseline`, `0002_security_contract_hardening` y el principal administrativo que aplicó cada una. La segunda retira `VENTAS_CREAR` de roles administradores existentes, sanea texto DDL legado y refuerza contratos. Estas marcas confirman aplicación administrativa, no autorizan migraciones desde el arranque de Express ni sustituyen su ensayo previo.

## Verificación del catálogo

La presencia de objetos puede inventariarse después de instalar, sin probar comportamiento:

```sql
SELECT s.name AS esquema, o.name, o.type_desc
FROM sys.objects AS o
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE s.name = N'dbo'
  AND (o.name LIKE N'sp[_]%' OR o.name LIKE N'fn[_]%' OR o.name LIKE N'trg[_]%')
ORDER BY o.type_desc, o.name;

SELECT s.name AS esquema, tt.name AS tipo_tabla
FROM sys.table_types AS tt
JOIN sys.schemas AS s ON s.schema_id = tt.schema_id
WHERE s.name = N'dbo'
ORDER BY tt.name;
```

`database/tests/01_contract.sql` automatiza el inventario y algunas firmas/reglas de la línea base; `02_pool_identity_pa29.sql` comprueba limpieza básica de contexto; `03_save-transaction.sql` demuestra savepoint; y `04_sale-rollback-fault.sql` fuerza y verifica un rollback posterior al encabezado sin persistir fixtures. `pnpm sql:verify` ejecuta únicamente `sp_VerificarEstado` con la cuenta de aplicación, mientras la suite de integración comprueba denegaciones directas del mismo login. Ninguna comprobación aislada demuestra todas las carreras, autorización extremo a extremo o continuidad: PA01–PA32 permanecen **Pendiente** hasta una corrida completa con evidencia enlazada.
