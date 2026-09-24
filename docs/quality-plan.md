# Plan de calidad QC01–QC08

Este documento define cómo medir los objetivos. No contiene resultados y un objetivo escrito no implica que exista el arnés para medirlo. Hasta completar una corrida válida con manifiesto, todos los QC permanecen **Pendiente**.

## Entorno obligatorio

- Base exclusiva de pruebas con Microsoft SQL Server real.
- API y navegador en el mismo equipo, por loopback.
- Cinco sesiones representan cinco clientes de prueba concurrentes en el mismo equipo.
- Equipo de referencia: al menos 16 GB de RAM y SSD, sin cargas intensivas durante la medición. No es un mínimo funcional del producto.
- Registrar CPU, RAM, almacenamiento, sistema operativo, navegador, Node, pnpm, SQL Server/edición/build y configuración relevante de base/pool.
- Dependencias fijadas por `pnpm-lock.yaml`; reloj estable y plan de energía documentado.

## Dataset prescrito

| Conjunto | Cantidad |
|---|---:|
| Clientes | 1,000 |
| Productos | 10,000 |
| Facturas | 50,000 |
| Líneas de factura | 250,000 |

Los datos son sintéticos e identificados como prueba. La semilla/generador debe ser reproducible y ejecutarse solo por el canal administrativo. No se vuelve a sembrar al iniciar la aplicación.

El repositorio actual no incluye el generador de este volumen ni el arnés concurrente de cinco sesiones. `database/seed-demo.sql` solo prepara un cliente y dos productos, por lo que no puede usarse para informar QC01, QC02 o PA30. El generador y el ejecutor de carga deben incorporarse o identificarse en el acta antes de abrir la corrida.

## Protocolo común de medición

1. Preparar la base exclusiva, comprobar conteos e integridad y registrar el hash/versión del dataset.
2. Reiniciar de forma documentada solo los componentes que el protocolo de la corrida indique; no limpiar cachés selectivamente entre muestras.
3. Ejecutar **20 operaciones de calentamiento por escenario**. No se incorporan al percentil.
4. Ejecutar **al menos 100 mediciones válidas por escenario**.
5. Para concurrencia, iniciar las cinco sesiones desde una barrera común y registrar la distribución real de inicios.
6. Medir extremo a extremo desde la petición hasta que los datos estén visibles y utilizables, no solo el tiempo SQL.
7. Separar rechazos funcionales esperados de errores técnicos. Registrar ambos, además del máximo.
8. Ordenar las duraciones válidas y calcular p95 con rango más cercano: posición `ceil(0.95 × N)`. Con 100 muestras corresponde a la muestra 95 ordenada.
9. Conservar datos crudos, resumen, errores y correlaciones. No redondear antes de calcular.

Un objetivo solo cumple si al menos 95 % de las mediciones válidas está bajo el umbral y no hay errores técnicos o pérdida de integridad que invalide la corrida.

## Objetivos

### QC01 — Consultas y reporte

**Objetivo:** consultas habituales p95 ≤ 2 s; reporte de hasta 366 días p95 ≤ 5 s.

Escenarios representativos mínimos:

- productos: primera página, búsqueda selectiva, filtro de estado y orden alternativo;
- clientes: búsqueda y cambio de página;
- ventas propias: lista y comprobante;
- auditoría: categoría y rango cuando el actor tenga permiso;
- reporte de ventas: rango de 366 días con totales del filtro completo.

La medición termina cuando filas, totales y estado accesible se muestran. Un error, respuesta incompleta o total calculado solo sobre la página invalida la muestra.

### QC02 — Venta concurrente

**Objetivo:** venta de hasta 100 líneas p95 ≤ 3 s con cinco sesiones concurrentes.

- Precrear cinco cajeros, clientes y productos con stock suficiente.
- Usar claves UUID diferentes entre ventas y conservar cada clave para reconciliación.
- Incluir el escenario máximo de 100 productos distintos; registrar también tamaños menores como diagnóstico.
- Verificar después de cada lote facturas, líneas, movimientos de caja, movimientos de stock, idempotencia y stock no negativo.
- Si hay una respuesta incierta, resolverla con la misma clave antes de contabilizar la muestra.

### QC03 — Integridad

**Objetivo:** cero ventas parciales, duplicadas o con stock negativo.

Ejecutar PA05–PA09 y PA22, incluyendo última unidad y fallos después de encabezado, detalle, stock, caja y auditoría. Consultas administrativas posteriores deben demostrar:

- toda factura confirmada tiene detalle y exactamente un movimiento de caja;
- no hay clave de idempotencia duplicada por usuario;
- no hay líneas duplicadas por producto dentro de factura;
- ningún stock es negativo;
- un fallo revierte todos sus efectos de negocio;
- la auditoría transaccional describe únicamente cambios persistidos.

### QC04 — Autorización

**Objetivo:** cero accesos indebidos en la matriz de permisos.

Ejecutar PA04, PA18, PA23 y PA25 por UI y por llamada HTTP directa. Probar Administrador sin `VENTAS_CREAR`, Cajero, Auditor, cuenta sin roles, cuenta inactiva y permiso revocado durante la sesión. Alternar identidades sobre el pool para confirmar aislamiento.

### QC05 — Usabilidad y accesibilidad

**Objetivo:** todas las acciones esenciales operables con teclado y ambos temas.

Ejecutar PA13–PA17 y PA24. Revisar acceso, inicio, nueva venta, comprobante y pantallas administrativas en Claro/Oscuro, 320/768/1280 px y texto al 200 %. Registrar contraste, foco, orden de tabulación, etiquetas, nombre accesible, diálogo, reducción de movimiento y desbordamiento.

La suite Playwright pública cubre acceso/recuperación/restablecimiento en dos temas y 320/768/1280. La suite privada recorre vistas esenciales de Administrador y Cajero contra API/SQL reales, usa Axe, controla desbordamiento y produce capturas en una base `_Test`. Aun así, teclado completo, zoom 200 %, edición con diálogos abiertos, cambio de sistema operativo y la matriz total de estados requieren el protocolo manual; esta automatización parcial no aprueba PA24.

### QC06 — Instalación y operación offline

**Objetivo:** arranque reproducible y operación sin Internet tras instalar dependencias.

En una copia limpia: instalar con lockfile congelado, preparar SQL, compilar, iniciar, ejecutar un recorrido esencial, desconectar Internet y repetir. Reiniciar API/SQL/equipo según el acta y comprobar persistencia. Corresponde a PA26 y PA32.

### QC07 — Continuidad

**Objetivo:** pérdida máxima de 24 h (RPO) y recuperación en 60 min (RTO).

Restaurar la última copia válida en una base diferente. Medir desde la declaración del incidente hasta la validación técnica y funcional. Verificar cuentas, factura, detalle, stock, caja, integridad y la invalidación de sesiones/tokens recuperados. Comparar la última transacción recuperada con la última conocida.

### QC08 — Trazabilidad

**Objetivo:** cada evento crítico identifica actor, fecha, resultado y operación.

Cruzar solicitud, respuesta, correlación y bitácora para acceso, cambio/restablecimiento de contraseña, permisos, usuario, rol, producto, inventario, cliente, venta y DDL. Confirmar que no aparecen secretos y que cada fallo interno conserva una referencia diagnóstica autorizada.

## Acta de corrida

| Campo | Valor |
|---|---|
| Identificador de corrida | Pendiente |
| Fecha/hora UTC | Pendiente |
| Responsable | Pendiente |
| Commit/paquete entregado | Pendiente |
| CPU / RAM / almacenamiento | Pendiente |
| SO / plan de energía | Pendiente |
| Navegador y versión | Pendiente |
| Node / pnpm | Pendiente |
| SQL Server edición/build/compatibilidad | Pendiente |
| Pool y timeouts | Pendiente |
| Dataset/semilla/conteos | Pendiente |
| Calentamiento | 20 por escenario, aún no ejecutado |
| Mediciones válidas requeridas | ≥100 por escenario, aún no ejecutadas |
| Errores/rechazos | Pendiente |
| Ruta de datos crudos | Pendiente |

## Registro de resultados

| QC | Estado | N válidas | N errores | p95 | Máximo | Objetivo | Evidencia/observaciones |
|---|---|---:|---:|---:|---:|---|---|
| QC01 consultas | Pendiente | — | — | — | — | ≤2 s | — |
| QC01 reporte 366 días | Pendiente | — | — | — | — | ≤5 s | — |
| QC02 venta 100 líneas/5 sesiones | Pendiente | — | — | — | — | ≤3 s | — |
| QC03 integridad | Pendiente | — | — | N/A | N/A | 0 anomalías | — |
| QC04 autorización | Pendiente | — | — | N/A | N/A | 0 accesos | — |
| QC05 usabilidad | Pendiente | — | — | N/A | N/A | 100 % esenciales | — |
| QC06 reproducibilidad/offline | Pendiente | — | — | N/A | N/A | Sin dependencia Internet | — |
| QC07 continuidad | Pendiente | — | — | — | — | RPO≤24 h; RTO≤60 min | — |
| QC08 trazabilidad | Pendiente | — | — | N/A | N/A | 100 % eventos críticos | — |
