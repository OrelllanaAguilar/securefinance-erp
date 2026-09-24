# Matriz de pruebas PA01–PA32

## Regla de estado

Todas las pruebas se inicializan en **Pendiente**. Solo una ejecución observable puede cambiar el estado:

- **Pendiente:** todavía no ejecutada.
- **En ejecución:** existe una corrida abierta.
- **Aprobada:** resultado observado coincide con todos los resultados esperados y la evidencia está enlazada.
- **Fallida:** uno o más resultados no coinciden; debe existir incidencia.
- **Bloqueada:** no puede ejecutarse por una causa externa concreta, por ejemplo SQL Server o navegador ausente. Un mock no desbloquea pruebas de ACID, TVP, concurrencia o restauración.

La lectura del código, una compilación correcta o una prueba parcial no autorizan a marcar una PA como Aprobada.

En esta revisión no existe `docs/evidence/manifest.csv`; por ello ninguna PA tiene evidencia oficial enlazada y PA01–PA32 continúan **Pendiente**.

## Definiciones

| ID | UC | Escenario | Resultado esperado | Estado inicial |
|---|---|---|---|---|
| PA01 | UC01, UC04 | Probar acceso con credenciales válidas, inválidas y una cuenta inactiva. | Solo la cuenta habilitada obtiene sesión. Los rechazos usan respuesta pública genérica y la bitácora registra el motivo interno sin secretos. | Pendiente |
| PA02 | UC02 | Cambiar la contraseña de una cuenta, comparar el salt y probar la contraseña anterior y la nueva. | Cambia el salt; la contraseña anterior falla; la nueva funciona; las sesiones y tokens anteriores quedan revocados. | Pendiente |
| PA03 | UC05 | Probar token de recuperación vencido, consumido y dos restablecimientos simultáneos con el mismo token. | Un token vencido o usado falla. En la carrera concurrente solo un restablecimiento consume el token y tiene éxito. | Pendiente |
| PA04 | UC04, UC06, UC07 | Como Cajero, manipular interfaz y llamar directamente endpoints de auditoría y roles. | La UI no ofrece las acciones y la API/SQL rechazan auditoría y roles; alterar el cliente nunca concede permiso. | Pendiente |
| PA05 | UC03 | Procesar una venta correcta y verificar factura, detalle, stock, caja e IVA con subtotal `100.00`. | Todos los efectos concuerdan en una sola venta; IVA `12.00`, total `112.00`; no hay efectos omitidos o duplicados. | Pendiente |
| PA06 | UC03 | Inyectar una falla después de crear el encabezado de factura. | No quedan factura parcial, detalle, movimiento de caja ni descuento de stock. El incidente técnico se registra después del rollback y por separado. | Pendiente |
| PA07 | UC03 | Con stock igual a uno, enviar dos ventas simultáneas por la última unidad. | Solo una venta se confirma; la otra recibe conflicto de stock; el stock final es cero, nunca negativo. | Pendiente |
| PA08 | UC03 | Enviar dos veces la misma venta y simular pérdida de la primera respuesta usando la misma clave y contenido. | La misma clave y contenido devuelve la misma factura; existe una factura y un movimiento de caja. | Pendiente |
| PA09 | UC03, UC08 | Actualizar varios productos en una sentencia y provocar también un rollback. | El trigger audita cada fila cambiada. La transacción revertida no conserva auditoría DML de cambios que no persistieron. | Pendiente |
| PA10 | UC03 | Enviar cantidades negativas, identificadores ajenos, precios alterados e intentos de inyección. | Los valores inválidos se rechazan; el texto de inyección se trata como dato; precios, impuestos, stock e identidad se obtienen de fuentes autorizadas. | Pendiente |
| PA11 | UC07, UC11, UC12 | Cerrar sesión, dejarla vencer, revocarla, desactivar usuario y retirar permisos durante una sesión. | Cookies cerradas/vencidas fallan; desactivar, revocar o cambiar permisos surte efecto en la siguiente operación protegida. | Pendiente |
| PA12 | UC04, UC10 | Comparar reportes con ventas confirmadas e intentar editar auditoría con la cuenta SQL de API. | El reporte contiene únicamente ventas confirmadas; la cuenta API no puede editar bitácoras; ninguna bitácora contiene secretos. | Pendiente |
| PA13 | UC13 | Recorrer toda la interfaz en Claro y Oscuro y cambiar tema con formularios/diálogos abiertos. | Ambos temas cubren toda la UI; el cambio no recarga, cierra diálogos ni borra formularios, filtros o venta en edición. | Pendiente |
| PA14 | UC13 | Seleccionar Sistema y cambiar `prefers-color-scheme`; repetir con Claro y Oscuro explícitos. | Solo Sistema sigue al sistema operativo. Claro y Oscuro permanecen fijos. Si no se detecta preferencia, Sistema resuelve a Claro. | Pendiente |
| PA15 | UC13 | Guardar Oscuro en cuenta A, Claro en B, alternar cuentas y cerrar sesión. | Cada cuenta recupera su preferencia sin mezclarla; al salir se restaura la preferencia anónima de acceso. | Pendiente |
| PA16 | UC13 | Forzar fallo al guardar apariencia, continuar usando la sesión y luego reintentar. | El tema se aplica en memoria; aparece «Aplicado en esta sesión; no se pudo guardar»; el reintento persiste y no afecta otras operaciones. | Pendiente |
| PA17 | UC13 | Hacer cambios rápidos de tema, probar navegador sin almacenamiento y sincronizar otra pestaña al recuperar foco. | Se conserva la última selección; sin almacenamiento local la sesión opera; otra pestaña actualiza al foco salvo que tenga un cambio local pendiente. | Pendiente |
| PA18 | UC06, UC14 | Iniciar como Cajero, probar métricas, URL/API prohibida, volver, recargar y alternar cuenta. | Cajero no ve métricas globales; URL y API prohibidas fallan; volver/recargar no revela datos de otra cuenta. | Pendiente |
| PA19 | UC14 | Probar Inicio durante carga, con cero datos, con una fuente fallida y al actualizar. | Carga, cero válido y fallo son distintos; hora/datos se actualizan; una tarjeta fallida no bloquea las demás. | Pendiente |
| PA20 | UC01–UC12 interactivos | Provocar validación y tratar de salir con cambios sin guardar; cambiar tema durante la edición. | El error identifica el campo y conserva valores no sensibles; el aviso permite permanecer; cambiar tema no avisa ni borra datos. | Pendiente |
| PA21 | Listados | Probar búsqueda, filtros, páginas 10/25/50, orden estable, totales y estados vacío/fallo. | Filtrar vuelve a página uno; el orden es estable; el total cubre todo el filtro; «sin registros», «sin coincidencias» y fallo de servicio no se confunden. | Pendiente |
| PA22 | UC03 | Provocar doble envío y pérdida/fallo de respuesta durante una venta. | El borrador queda pendiente con la misma clave; se resuelve en una sola factura; no se habilita nueva clave mientras el resultado sea incierto. | Pendiente |
| PA23 | UC06, UC12, UC14 | Vencer sesión, abrir ruta inexistente/prohibida y probar una cuenta sin roles. | Vencimiento limpia datos sensibles; ruta inexistente ofrece volver a Inicio; ruta prohibida rechaza; sin roles conserva solo funciones personales. | Pendiente |
| PA24 | Todos | Operar acceso y venta solo con teclado, revisar foco/etiquetas/contraste, zoom 200 % y anchos 320/768/1280 en ambos temas. | Las acciones esenciales son operables, el foco es visible y controlado, hay nombres accesibles, el contraste cumple y el contenido general no desborda. | Pendiente |
| PA25 | UC03, UC10 | Consultar e imprimir comprobantes como Cajero y como usuario con `REPORTES_LEER`, desde tema Oscuro. | Cajero solo accede a facturas propias; `REPORTES_LEER` accede a todas; la impresión es clara sobre fondo blanco y no crea otra venta. | Pendiente |
| PA26 | Todos | Desconectar Internet después de instalar; detener API o base durante una operación. | El sistema local funciona sin Internet. Una caída de API/BD se informa como fallo y nunca confirma una operación ni presenta cero válido. | Pendiente |
| PA27 | Transversal | Probar mínimos/máximos, un valor por encima, campos inesperados y versiones obsoletas en ediciones concurrentes. | Los límites se aplican sin truncado; campos extra se rechazan; no hay duplicados ni sobrescritura silenciosa; una versión obsoleta devuelve conflicto. | Pendiente |
| PA28 | UC03, UC08, UC10 | Vender, cambiar cliente/producto/precio, reimprimir y probar subtotal `0.05`. | El comprobante histórico permanece idéntico; IVA `0.01`, total `0.06`; los cambios de catálogo no reescriben la venta. | Pendiente |
| PA29 | UC01, UC04, UC06; transversal | Alternar cuentas sobre conexiones reutilizadas, enviar otro `UsuarioId` e inspeccionar auditoría y permisos. | Identidad, permisos y auditoría proceden de la sesión; el identificador del navegador y un contexto residual del pool no cambian el actor. | Pendiente |
| PA30 | UC03, UC10; QC01, QC02 | Ejecutar carga con el dataset prescrito, cinco sesiones y registrar equipo, errores, máximos y percentiles. | Las mediciones válidas producen percentiles reproducibles sin errores, pérdida de integridad ni afirmaciones sin acta. | Pendiente |
| PA31 | QC07 | Restaurar la última copia válida en otra base y verificar cuentas, factura, detalle, stock y caja. | La base restaurada es íntegra; se registran pérdida y duración frente a RPO 24 h/RTO 60 min; sesiones y tokens recuperados se invalidan. | Pendiente |
| PA32 | QC06 | En una copia limpia, preparar SQL, instalar con lockfile, compilar, iniciar y reiniciar sin Internet. | El arranque es reproducible; el reinicio conserva facturas y configuración; el runtime funciona offline con API y SQL activos. | Pendiente |

## Preparación pendiente para ejecutar la matriz

Estos huecos del paquete no cambian automáticamente el estado a `Bloqueada`; identifican trabajo previo para poder abrir una corrida válida.

| Alcance | Herramienta existente | Hueco que debe resolverse o cubrirse manualmente |
|---|---|---|
| PA01–PA05, PA08, PA10–PA12, PA18–PA23, PA25, PA27–PA29 | Aplicación, API, scripts SQL y semilla pequeña `_Test` | Preparar datos/roles exclusivos, coordinador de casos, capturas y consultas posteriores; registrar revisión y entorno. |
| PA03, PA07, PA08, PA22, PA29 | Casos SQL parciales y endpoints funcionales | Hace falta coordinación simultánea real. Llamadas secuenciales o mocks no acreditan una carrera ni reutilización del pool. |
| PA06 y rollback por etapa de QC03 | `database/tests/04_sale-rollback-fault.sql` crea un trigger temporal dentro de la transacción en una base `_Test` y verifica el punto posterior al encabezado | Añadir otros puntos de fallo si el protocolo exige cobertura por etapa y conservar salida/entorno en el manifiesto; la cuenta API no puede activar este mecanismo. |
| PA09 | Triggers por conjuntos | Preparar DML administrativo multirregistro y una transacción revertida; verificar una fila de auditoría por registro y ausencia tras rollback. |
| PA13–PA17 y PA24 | Vitest/RTL, Playwright público en 18 combinaciones y recorrido privado real de 14 vistas con Axe/capturas | Ejecutar todavía teclado, zoom 200 %, diálogos/formularios durante cambio de tema, preferencia Sistema y estados de fallo; la suite actual es parcial. |
| PA30 / QC01–QC02 | Plan de medición | No hay generador del dataset prescrito ni arnés de cinco sesiones/percentiles. La semilla demo no cumple el volumen. |
| PA31 / QC07 | Scripts de backup, verificación y restauración | Ejecutar restauración aislada, cronometrar RPO/RTO y conservar manifiesto/hash/validaciones; `VERIFYONLY` solo no basta. |
| PA32 / QC06 | Instalador, lockfile, build/start | Ejecutar desde copia limpia y repetir sin Internet después de obtener dependencias; una compilación en el workspace actual no acredita reproducibilidad. |

## Registro de ejecución

Cada fila debe completarse durante una ejecución real. `Evidencia` utiliza rutas relativas conforme a [Guía de evidencia](evidence-guide.md). No se registran contraseñas, tokens, cookies, hashes, salts ni cadenas de conexión.

| ID | Estado | Fecha/hora UTC | Entorno y versiones | Datos/precondiciones | Resultado observado | Evidencia | Ejecutor | Incidencia/bloqueo |
|---|---|---|---|---|---|---|---|---|
| PA01 | Pendiente | — | — | — | — | — | — | — |
| PA02 | Pendiente | — | — | — | — | — | — | — |
| PA03 | Pendiente | — | — | — | — | — | — | — |
| PA04 | Pendiente | — | — | — | — | — | — | — |
| PA05 | Pendiente | — | — | — | — | — | — | — |
| PA06 | Pendiente | — | — | — | — | — | — | — |
| PA07 | Pendiente | — | — | — | — | — | — | — |
| PA08 | Pendiente | — | — | — | — | — | — | — |
| PA09 | Pendiente | — | — | — | — | — | — | — |
| PA10 | Pendiente | — | — | — | — | — | — | — |
| PA11 | Pendiente | — | — | — | — | — | — | — |
| PA12 | Pendiente | — | — | — | — | — | — | — |
| PA13 | Pendiente | — | — | — | — | — | — | — |
| PA14 | Pendiente | — | — | — | — | — | — | — |
| PA15 | Pendiente | — | — | — | — | — | — | — |
| PA16 | Pendiente | — | — | — | — | — | — | — |
| PA17 | Pendiente | — | — | — | — | — | — | — |
| PA18 | Pendiente | — | — | — | — | — | — | — |
| PA19 | Pendiente | — | — | — | — | — | — | — |
| PA20 | Pendiente | — | — | — | — | — | — | — |
| PA21 | Pendiente | — | — | — | — | — | — | — |
| PA22 | Pendiente | — | — | — | — | — | — | — |
| PA23 | Pendiente | — | — | — | — | — | — | — |
| PA24 | Pendiente | — | — | — | — | — | — | — |
| PA25 | Pendiente | — | — | — | — | — | — | — |
| PA26 | Pendiente | — | — | — | — | — | — | — |
| PA27 | Pendiente | — | — | — | — | — | — | — |
| PA28 | Pendiente | — | — | — | — | — | — | — |
| PA29 | Pendiente | — | — | — | — | — | — | — |
| PA30 | Pendiente | — | — | — | — | — | — | — |
| PA31 | Pendiente | — | — | — | — | — | — | — |
| PA32 | Pendiente | — | — | — | — | — | — | — |

## Datos y mecanismos especiales

- PA03, PA07, PA08, PA22 y PA29 requieren coordinación concurrente real, no llamadas secuenciales presentadas como carrera.
- PA05–PA09 y PA22 usan SQL Server real y verificaciones posteriores desde un canal administrativo de solo prueba.
- PA06 y PA09 usan inyección de fallos aislada, imposible de activar desde la cuenta o servicio normal.
- PA24 registra tema, viewport, zoom, navegador, entrada utilizada y violación concreta, no solo una captura visual.
- PA30 sigue las condiciones de [Plan QC](quality-plan.md).
- PA31 restaura siempre en otra base; nunca reemplaza automáticamente la base existente.
