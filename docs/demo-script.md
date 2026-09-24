# Guion de demostración — 12 minutos

## Preparación previa

- Usar una base de demostración identificada, nunca datos reales.
- Tener API y SQL Server activos, frontend compilado y conectividad de loopback verificada.
- Preparar credenciales privadas temporales para Administrador, Cajero y Auditor; no mostrarlas en pantalla ni incluirlas en el repositorio.
- Tener productos con stock, un cliente, una clave de venta aún no usada y un comprobante histórico.
- Cerrar herramientas que puedan mostrar secretos. Confirmar que la demo no se presenta como evidencia de PA aprobadas.

## Recorrido cronometrado

| Tiempo | Acción | Mensaje clave |
|---|---|---|
| 00:00–00:40 | Presentar arquitectura local y estado de la entrega. | React y Express operan bajo un origen; Express llama SP en SQL Server. Las pruebas/métricas solo se afirman con evidencia. |
| 00:40–01:30 | Abrir `/acceso`, alternar Claro/Oscuro/Sistema e iniciar como Cajero. | Preferencia anónima separada; cookie opaca HttpOnly; el Cajero no recibe funciones administrativas. |
| 01:30–03:15 | En `/ventas/nueva`, buscar cliente/productos, cambiar cantidades y cotizar. | SQL decide precio, stock, subtotal e IVA; el navegador no envía precios autoritativos. Mostrar subtotal, IVA y total como cadenas de dos decimales. |
| 03:15–04:20 | Confirmar una venta y abrir `/ventas/:id`. | Factura, detalle, stock, caja y auditoría se confirman en una transacción. La clave UUID evita duplicados. |
| 04:20–05:00 | Abrir impresión/vista previa. | El comprobante es histórico, de solo lectura, fondo blanco; imprimir no crea otra venta. |
| 05:00–05:40 | Mostrar `/ventas` y explicar “Resultado desconocido”. | Ante pérdida de respuesta se conserva la misma clave y se consulta el resultado; no se repite manualmente con otra clave. |
| 05:40–06:35 | Entrar como Administrador; abrir productos y realizar un ajuste con motivo. | Producto inicia con stock cero; el ajuste es transaccional, exige motivo y `rowversion`; el historial no se reescribe. |
| 06:35–07:15 | Mostrar clientes y estados activos/inactivos. | Se desactiva en lugar de borrar para conservar comprobantes históricos. Paginación y filtros ocurren en servidor. |
| 07:15–08:00 | Abrir reporte de ventas y filtrar fechas. | `REPORTES_LEER` ve todas las facturas y totales del filtro completo; un fallo no se presenta como cero. |
| 08:00–08:50 | Entrar como Auditor y recorrer Accesos, DML y DDL. | Mostrar actor de aplicación, principal SQL, IP, fecha, operación y resultado; revisar la muestra sin asumir ni exponer secretos. |
| 08:50–09:45 | Mostrar usuarios, roles y permisos; explicar permisos efectivos del Administrador. | El bootstrap excluye `VENTAS_CREAR`; vender requiere un rol explícito. El nombre del rol no sustituye permisos y la API vuelve a validarlos en cada operación. |
| 09:45–10:35 | Mostrar perfil, cambio de contraseña y recuperación local. | Política 12–128 sin recorte; SHA2_512+salt es perfil académico; token de 15 minutos, digest y un solo uso. |
| 10:35–11:15 | Cerrar sesión y comprobar restauración del tema anónimo; mencionar expiración/revocación. | Cerrar limpia datos sensibles. Cambiar roles/desactivar usuario afecta la siguiente operación protegida. |
| 11:15–12:00 | Cerrar con matriz PA/QC, respaldo y limitaciones reales. | PA inicia Pendiente; QC exige dataset/medición. Express no tiene SQL Agent: respaldos con Task Scheduler. No afirmar “producción”. |

## Variante didáctica de `SAVE TRANSACTION`

Ejecutar únicamente en la base de pruebas y fuera del flujo de venta:

1. abrir transacción;
2. crear un savepoint;
3. efectuar una modificación didáctica no comercial;
4. provocar una condición controlada;
5. consultar `XACT_STATE()`;
6. hacer rollback al savepoint solo cuando el estado lo permita;
7. revertir finalmente toda la transacción didáctica.

Explicar que una venta no usa el savepoint para conservar encabezado, detalle o caja parciales: ante cualquier fallo se revierte completa.
