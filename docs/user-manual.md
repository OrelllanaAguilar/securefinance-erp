# Manual de usuario

## Antes de empezar

SecureFinance ERP es una aplicación local. Para utilizarla deben estar activos SQL Server y la API en el equipo autorizado. El runtime está diseñado sin CDN ni servicio externo, pero la operación sin Internet todavía debe comprobarse mediante PA26/PA32. Una conexión a Internet no sustituye una API o base detenida.

Use una cuenta individual. No comparta contraseñas, credenciales temporales, enlaces de recuperación ni capturas con datos privados. Los menús dependen de los permisos de la cuenta y una opción ausente no se habilita cambiando la URL.

## Acceso y sesión

### Iniciar sesión

1. Abra `/acceso`.
2. Escriba el usuario y la contraseña exactamente como fueron entregados. El usuario admite letras ASCII, números, punto, guion y guion bajo.
3. Seleccione **Acceder**.
4. Si la credencial es temporal, el sistema conduce a `/perfil/seguridad`; los demás módulos permanecen bloqueados hasta cambiarla.

Los mensajes de credencial inválida o cuenta inactiva son deliberadamente generales. Después de varios intentos puede aparecer una espera por limitación; no repita envíos rápidos.

### Cerrar sesión

Abra el menú de la cuenta en el encabezado y elija **Cerrar sesión**. La sesión del servidor se revoca, la cookie se elimina y se vuelve a `/acceso`. Cierre sesión antes de dejar el equipo; cerrar solamente una pestaña no equivale a cerrar la sesión.

La sesión también termina por inactividad, vencimiento absoluto, desactivación de cuenta, cambio de contraseña o cambio de permisos. Si ocurre, se limpian los datos privados en memoria y se solicita acceso de nuevo.

## Recuperación y contraseñas

### Recuperar acceso

1. Desde `/acceso`, elija **Recuperar acceso**.
2. Escriba usuario o correo y seleccione **Solicitar recuperación**.
3. La respuesta siempre indica que la solicitud fue recibida. Si la cuenta existe y está habilitada, el administrador encontrará la instrucción en el canal privado configurado.
4. Abra el enlace de `/restablecer` antes de 15 minutos. Es de un solo uso.
5. Escriba y confirme la contraseña nueva.

Nunca solicite que el enlace o token se publique en una captura, chat o incidencia. Un enlace vencido o consumido debe reemplazarse con una solicitud nueva.

### Cambiar contraseña

En el menú de la cuenta, abra **Seguridad**. Introduzca la contraseña actual o temporal, la nueva y su confirmación. La contraseña nueva debe tener:

- entre 12 y 128 caracteres;
- al menos una mayúscula y una minúscula;
- al menos un número;
- al menos un símbolo.

No se eliminan espacios al principio o al final. Tras el cambio, todas las sesiones y tokens de recuperación anteriores quedan revocados y se debe iniciar sesión con la contraseña nueva.

## Apariencia: Claro, Oscuro y Sistema

El selector **Apariencia** está disponible en las pantallas públicas, el encabezado privado y **Mi perfil**.

| Opción | Comportamiento |
|---|---|
| **Claro** | Fondo cálido claro y superficies blancas; no sigue cambios del sistema operativo. |
| **Oscuro** | Fondo grafito y superficies oscuras; no sigue cambios del sistema operativo. |
| **Sistema** | Sigue `prefers-color-scheme`; si el navegador no lo ofrece, resuelve a Claro. |

Cambiar la opción no recarga la página ni debe borrar formularios, filtros, diálogos o una venta en edición. Antes de acceder, la preferencia es anónima y pertenece al navegador. Después de acceder, se usa la preferencia de la cuenta almacenada en SQL. Al cerrar sesión se restaura la preferencia anónima, de modo que las cuentas no comparten tema.

Si el guardado falla, el tema se mantiene durante la sesión y aparece **«Aplicado en esta sesión; no se pudo guardar»**. Seleccione **Reintentar** cuando el servicio vuelva. Los cambios rápidos se serializan y la última selección es la deseada. Otra pestaña actualiza la preferencia al recuperar foco, salvo que tenga un cambio local pendiente.

La impresión del comprobante siempre usa fondo claro, aun si la pantalla está en Oscuro; no modifica la preferencia.

## Navegación y permisos

En escritorio, use la barra lateral. En pantallas estrechas, abra **Menú** en el encabezado y ciérrelo después de elegir una ruta. El enlace **Saltar al contenido** permite omitir la navegación con teclado.

| Opción | Quién suele verla | Uso |
|---|---|---|
| Inicio | cualquier sesión válida | Tareas autorizadas y, con `REPORTES_LEER`, resumen disponible. |
| Nueva venta | `VENTAS_CREAR` | Cotizar y confirmar una venta. |
| Facturas / Mis ventas | `VENTAS_CREAR` o `REPORTES_LEER` | Consultar e imprimir comprobantes autorizados. |
| Productos | venta o gestión de productos | Consulta; mantenimiento/stock solo con gestión. |
| Clientes | venta o gestión de clientes | Consulta; mantenimiento solo con gestión. |
| Reportes | `REPORTES_LEER` | Ventas confirmadas por rango. |
| Auditoría | `AUDITORIA_LEER` | Accesos, DML y DDL. |
| Usuarios | `USUARIOS_GESTIONAR` | Cuentas, estado, roles y credencial temporal. |
| Roles y permisos | `ROLES_GESTIONAR` | Roles y permisos efectivos. |
| Mi perfil / Seguridad | cualquier sesión válida | Datos propios, apariencia y contraseña. |

Una ruta inexistente muestra **Página no encontrada** y permite volver a Inicio. Una ruta conocida sin permiso muestra **Acceso no autorizado**. Volver, recargar o alterar la interfaz no debe exponer contenido de otra cuenta.

## Inicio

`/inicio` muestra saludo, hora de actualización y accesos rápidos compatibles con la cuenta. Quien posee `REPORTES_LEER` puede ver el resumen autorizado; un Cajero sin ese permiso no ve métricas globales.

Distinga estos estados:

- **Preparando/Cargando:** aún no hay resultado.
- **Cero:** la consulta terminó correctamente y el valor es cero.
- **Sin datos:** no existen filas para ese alcance.
- **Error:** el servicio no pudo completar una fuente; use **Reintentar**.

Un error no representa cero. Actualizar debe volver a pedir los datos y cambiar la hora mostrada.

## Registrar una venta

### 1. Cliente

En `/ventas/nueva`, busque por nombre o identificación y elija un cliente activo. Si no aparece, revise la búsqueda o solicite a quien posea `CLIENTES_GESTIONAR` que lo cree/active.

### 2. Productos

Busque código o descripción y agregue productos con existencia. Cada producto aparece una sola vez; aumente o reduzca su cantidad en la línea. Se permiten hasta 100 productos distintos y de 1 a 9999 unidades por producto. El borrador vive solo en memoria y se pierde al abandonar la página o terminar la sesión.

### 3. Cotización

Seleccione **Cotizar venta**. SQL Server obtiene precios y existencias actuales y devuelve subtotal, IVA y total. El precio mostrado antes de confirmar no procede de un valor editable del navegador. Si cambia cliente, producto o cantidad, actualice la cotización.

### 4. Confirmación

Revise cliente, líneas, subtotal, IVA y total; luego seleccione **Confirmar venta** y confirme el diálogo. Una venta correcta abre o permite abrir su comprobante. No actualice la página ni pulse repetidamente mientras está en curso.

Si aparece **Resultado desconocido**, no cree otra venta ni cambie la clave del borrador. Use **Consultar resultado**. La aplicación consulta la misma operación hasta encontrar la factura o mantenerla pendiente. Después de una sesión nueva, revise **Mis ventas** antes de repetir manualmente.

### Conflictos

- **Existencia insuficiente:** ajuste cantidades y vuelva a cotizar; otra sesión pudo consumir el stock.
- **Total cambió:** revise la cotización actual; no fuerce el total anterior.
- **Resultado desconocido:** conserve la operación y resuelva con la misma clave.
- **Servicio no disponible:** no se considera confirmada; si el envío pudo alcanzar el servidor, reconcilie primero.

## Facturas y comprobantes

En `/ventas`, un Cajero ve sus propias facturas. Un usuario con `REPORTES_LEER` puede seleccionar alcance **Todas** o **Propias**. Filtre por factura/cliente y fechas. Aplicar un filtro vuelve a la página 1; puede mostrar 10, 25 o 50 filas.

Abra una factura para ver cliente y cajero históricos, líneas, cantidades, precios, subtotal, IVA y total. Seleccione **Imprimir** para la vista del navegador. Consultar o imprimir nunca registra otra venta. Los cambios posteriores de cliente, producto o precio no reescriben el comprobante.

## Productos e inventario

Quien vende puede consultar productos activos y stock. Con `PRODUCTOS_GESTIONAR` también puede:

### Crear o editar

1. Seleccione **Nuevo producto** o el icono **Editar**.
2. Complete código (1–30), descripción (2–160), unidad del catálogo y precio sin IVA (`0.01–999999.99`).
3. Guarde. Un producto nuevo comienza con stock 0.

Desactive un producto en vez de borrarlo. Si otra persona lo actualizó, se muestra conflicto de edición; cierre/recargue, revise el dato vigente y repita conscientemente.

### Ajustar inventario

1. Elija **Ajustar inventario**.
2. Introduzca un entero positivo para entrada o negativo para salida; no use cero.
3. Escriba un motivo de 10–250 caracteres.
4. Confirme.

El stock nunca puede quedar negativo. Todo ajuste conserva stock anterior/nuevo, actor, motivo, fecha y correlación.

## Clientes

Quien vende puede buscar clientes activos. Con `CLIENTES_GESTIONAR`, seleccione **Nuevo cliente** o **Editar** y complete:

- identificación: 1–30;
- nombre o razón social: 2–120;
- correo opcional: hasta 254;
- teléfono opcional: hasta 30.

Desactivar conserva las facturas históricas. Un conflicto indica que el registro cambió desde que se abrió; recargue y revise antes de sobrescribir.

## Reportes de ventas

Con `REPORTES_LEER`, abra `/reportes/ventas`, indique **Desde** y **Hasta** y aplique. El intervalo máximo es 366 días inclusivos. La tabla contiene ventas confirmadas y los totales corresponden a todo el filtro, no solo a la página visible.

Una tabla vacía significa consulta correcta sin filas. Un panel de error significa que no hay resultado fiable; no copie ceros como métricas. Abra el detalle desde la fila para consultar/imprimir la factura histórica.

## Auditoría

Con `AUDITORIA_LEER`, abra `/auditoria` y seleccione:

- **Accesos:** intentos, resultado público/interno autorizado, actor si fue resuelto, IP y correlación.
- **Cambios DML:** tabla, operación, registro, actor de aplicación, principal SQL e imágenes anterior/nueva sanitizadas.
- **Esquema DDL:** evento, tipo/nombre/esquema del objeto, principal SQL y contexto. Por minimización de datos no se conserva el texto del comando.

Use búsqueda, rango y paginación. La auditoría es de solo lectura desde la cuenta de aplicación. No debe contener contraseñas, hashes, salts, cookies, tokens o cadenas de conexión; si observa uno, limite acceso a la evidencia y abra una incidencia de seguridad.

## Usuarios

Con `USUARIOS_GESTIONAR`:

1. Cree una cuenta con usuario, nombre visible, correo opcional y roles.
2. Copie la contraseña temporal solo en el momento mostrado y entréguela por un canal privado. No la incluya en evidencia.
3. El usuario debe cambiarla al primer acceso.
4. Para editar, cambie nombre, correo, estado o roles y guarde con la versión vigente.
5. **Restablecer contraseña** genera otra credencial temporal, revoca sesiones/tokens y vuelve obligatorio el cambio.

Desactivar o cambiar roles afecta la siguiente operación protegida. El sistema impide dejar la instalación sin un administrador operativo. No intente resolver ese control desde la interfaz del navegador.

## Roles y permisos

Con `ROLES_GESTIONAR`, cree o edite nombre (3–60), descripción, estado y permisos. Los permisos disponibles son los siete códigos documentados en [Contratos API](api-contracts.md). Guardar un cambio revoca sesiones de usuarios afectados para que la autorización no quede obsoleta.

El rol administrador protegido no puede perder `USUARIOS_GESTIONAR` ni `ROLES_GESTIONAR`, ni desactivarse. El aprovisionamiento bootstrap excluye `VENTAS_CREAR`: el nombre `Administrador` no permite vender por sí solo y esa capacidad debe asignarse explícitamente mediante otro rol.

## Perfil

`/perfil` presenta datos propios, roles y permisos efectivos, junto con el selector de apariencia. Es informativo: un permiso que no aparece no se obtiene editando la página. Use **Cambiar contraseña** para ir a Seguridad.

## Formularios, tablas y accesibilidad

- Use `Tab`/`Shift+Tab` para avanzar/retroceder, `Enter` o `Espacio` para activar controles y `Escape` para cerrar un diálogo cuando esté disponible.
- El foco visible indica dónde actuará el teclado. Al abrir/cerrar un diálogo debe moverse y regresar de forma controlada.
- Los errores señalan el campo y conservan datos no sensibles. Contraseñas/tokens pueden limpiarse por seguridad.
- Antes de salir con cambios operativos sin guardar, lea el aviso y elija permanecer o salir. Cambiar solo el tema no cuenta como cambio del negocio.
- En tablas anchas use el desplazamiento interno. A 200 % o en móvil, la navegación cambia a menú y los paneles se apilan.

## Resolución rápida de problemas

| Mensaje/síntoma | Acción segura |
|---|---|
| «Tu sesión terminó» | Vuelva a `/acceso`; no reutilice formularios privados de la sesión anterior. |
| «No tienes permiso» | Confirme la cuenta/rol con un administrador; no altere la URL. |
| «La información cambió» | Recargue el registro, compare y vuelva a aplicar el cambio. |
| «No hay existencias suficientes» | Reduzca cantidad o solicite un ajuste autorizado; vuelva a cotizar. |
| «No se pudo conectar con el servicio» | Compruebe API/SQL; no interprete el fallo como operación confirmada. |
| «Resultado desconocido» en venta | Mantenga la misma clave y use **Consultar resultado** o **Mis ventas**. |
| Tema aplicado pero no guardado | Continúe si lo desea y use **Reintentar** cuando la API regrese. |
| Página no encontrada | Seleccione **Ir al inicio** y use la navegación disponible. |

Las conductas descritas son el contrato y la guía operativa esperados, no un acta de ejecución. Autenticación, ventas, permisos, visuales, teclado, concurrencia, continuidad y operación offline solo se declaran observados después de ejecutar la PA correspondiente y adjuntar evidencia. PA01–PA32 permanecen **Pendiente**.
