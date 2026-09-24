# Decisiones técnicas

Las decisiones siguientes son reversibles salvo las reglas funcionales impuestas por la especificación. “Aceptada” significa que guía esta implementación; no equivale a certificación de seguridad o producción.

## DT01 — JavaScript y workspace pnpm

**Estado:** aceptada.

El repositorio usa JavaScript moderno `.js/.jsx`, ESM y un workspace pnpm con `apps/web` y `apps/api`. Las versiones se fijan exactamente y `pnpm-lock.yaml` es la única fuente de resolución. No se generan `package-lock.json` ni `yarn.lock`.

## DT02 — SPA y API bajo un mismo origen

**Estado:** aceptada.

Vite se usa en desarrollo con proxy; en ejecución integrada Express sirve el frontend compilado. Esto permite cookie de mismo sitio, elimina CORS abierto y simplifica CSRF. Ambos servicios se enlazan a loopback, nunca a `0.0.0.0` por defecto.

## DT03 — SQL Server como frontera de integridad

**Estado:** aceptada y obligatoria.

La API ejecuta procedimientos almacenados; las TVF se consumen dentro de procedimientos. La cuenta de aplicación no recibe DML directo, DDL, `db_owner` ni `sysadmin`. Instalación y migración pertenecen a una cuenta administrativa y nunca se ejecutan al arrancar el servicio.

## DT04 — Sesión opaca, cookie y CSRF

**Estado:** aceptada.

La cookie contiene un token aleatorio opaco. SQL conserva solo `SHA2_512(token)`. En cada operación se validan usuario activo, revocación, inactividad de 30 minutos, duración absoluta de ocho horas y permisos actuales. El token CSRF se deriva con HMAC-SHA-256 y se compara en tiempo constante; los métodos de escritura también validan el origen.

No se almacenan credenciales ni sesiones en `localStorage`. Al finalizar una sesión se eliminan token CSRF, datos privados y borradores sensibles en memoria.

## DT05 — Perfil académico de contraseñas SHA2_512

**Estado:** aceptada por requisito académico, con riesgo explícito.

SQL genera un salt criptográfico individual y calcula `HASHBYTES('SHA2_512', salt + representación inequívoca de la contraseña)`. La contraseña conserva exactamente los 12–128 caracteres recibidos: no se recorta, normaliza ni trunca. La contraseña en claro atraviesa navegador y API para llegar al parámetro SQL, pero no se persiste, registra ni devuelve; hash y salt permanecen en tablas SQL y tampoco se proyectan por la API ni se incluyen en auditoría.

SHA2_512 es rápido y **no es un verificador de contraseña con factor de trabajo**. Esta decisión satisface la rúbrica académica, pero no convierte al sistema en “listo para producción”. Antes de una publicación real se requiere una migración versionada a Argon2id, scrypt, bcrypt o PBKDF2 con parámetros vigentes, rehash progresivo, pruebas de compatibilidad y plan de reversión.

## DT06 — Recuperación de un solo uso

**Estado:** aceptada.

La API genera un token aleatorio, SQL guarda su digest, su vigencia es de 15 minutos y el consumo es atómico. La respuesta pública siempre es genérica. El token solo se entrega mediante un buzón local privado fuera de `apps/web`/`dist`. Cambiar o restablecer contraseña revoca sesiones y tokens anteriores.

## DT07 — Parámetros tipados, TVP y permisos mínimos

**Estado:** aceptada y obligatoria.

`mssql` declara explícitamente longitud, precisión y tipo de cada parámetro. El detalle de una venta viaja como `dbo.TVP_DetalleFactura`; el navegador nunca genera SQL.

La cuenta API necesita, además de `EXECUTE` sobre los SP autorizados, permisos sobre el tipo concreto:

```sql
GRANT EXECUTE ON TYPE::dbo.TVP_DetalleFactura TO SecureFinanceApiExecutor;
GRANT REFERENCES ON TYPE::dbo.TVP_DetalleFactura TO SecureFinanceApiExecutor;
```

No se concede `EXECUTE` o `REFERENCES` indiscriminado a todos los tipos o a toda la base. `SecureFinanceApiExecutor` es el rol de base; el login/usuario concreto se aprovisiona por variables SQLCMD privadas y se agrega solo a ese rol.

## DT08 — Importes exactos

**Estado:** aceptada.

SQL usa `DECIMAL(19,2)`. El HTTP usa cadenas decimales y la API valida formato y rango. Tedious materializa `DECIMAL/NUMERIC` como `Number`, por lo que los SP de consulta proyectan importes públicos como texto con dos decimales. La interfaz puede usar aritmética decimal explícita para presentación, pero la cotización y confirmación autoritativas siempre proceden de SQL.

Casos de control obligatorios:

- `100.00` → IVA `12.00` → total `112.00`.
- `0.05` → IVA `0.01` → total `0.06`.

## DT09 — Idempotencia de venta

**Estado:** aceptada.

La clave es un UUID ligado al usuario y a una huella canónica de cliente/productos/cantidades/total aceptado. Existe unicidad por usuario y clave. Solicitudes concurrentes de la misma clave se serializan. Una clave repetida con la misma huella recupera la factura; con otra huella devuelve conflicto.

Un error de transporte o `5xx` no prueba rollback. La API responde “resultado desconocido”, conserva la clave y consulta `sp_ConsultarResultadoVenta` hasta obtener un estado definitivo.

## DT10 — Transacción de venta y fallos de prueba

**Estado:** aceptada.

Factura, detalle, descuento de stock, movimiento de caja y auditoría DML comparten una transacción con `SET XACT_ABORT ON`, `TRY/CATCH`, `COMMIT` y `ROLLBACK`. El stock se bloquea/actualiza en orden estable. El código intenta registrar un incidente técnico después del rollback en una tabla separada; PA06 debe demostrar ambos efectos contra SQL Server.

`database/tests/04_sale-rollback-fault.sql` implementa un punto de fallo posterior al encabezado sin añadir ramas de prueba al SP: crea un trigger temporal de nombre único y todos los fixtures dentro de una transacción externa; el `ROLLBACK` del procedimiento elimina sus filas. El script exige conexión administrativa y nombre `_Test`, comprueba la ausencia de factura/detalle/caja/auditoría y fixtures, valida el incidente y lo limpia al terminar. Los contadores `IDENTITY` y la secuencia pueden dejar huecos normales. Es evidencia automatizable de un punto, no autorización para marcar PA06 sin el acta completa. `03_save-transaction.sql` conserva únicamente su propósito didáctico.

## DT11 — Contexto de auditoría por conexión

**Estado:** aceptada.

La API pasa hash de sesión, IP observada y correlación. SQL resuelve el actor desde la sesión y establece `SESSION_CONTEXT` en la misma conexión de la operación. El contexto se limpia antes de devolver la conexión al pool. El navegador no selecciona `UsuarioId`.

## DT12 — Control de concurrencia optimista

**Estado:** aceptada.

Productos, clientes, usuarios y roles exponen una versión `rowversion`. Toda edición envía la versión leída; una versión obsoleta produce `409 STALE_VERSION`. El stock solo cambia mediante ajuste transaccional con motivo de 10–250 caracteres.

## DT13 — Temas por navegador y por cuenta

**Estado:** aceptada.

La preferencia anónima pertenece al navegador; la autenticada se guarda en SQL. El cambio se aplica antes de persistir, se serializa y una respuesta antigua no puede revertir el último valor. Al salir se restaura la preferencia anónima. Una lectura de sincronización fallida conserva el valor actual y no sobrescribe la cuenta.

## DT14 — Errores públicos y correlación

**Estado:** aceptada.

La API distingue `400`, `401`, `403`, `404`, `409`, `429` y `503`. Cada error usa mensaje en español, código estable y `correlationId`; nunca contiene texto SQL, stack ni secretos. Los registros internos conservan solo los datos técnicos necesarios y permiten seguir la misma correlación.

## DT15 — SQL Server Express y continuidad

**Estado:** aceptada para el entorno local.

SQL Server Express no incluye SQL Server Agent. La política requiere programar la copia diaria con Task Scheduler y PowerShell/sqlcmd, conservar al menos siete copias protegidas y una en otro medio. El repositorio aporta scripts SQL y una guía, no una tarea ya instalada. Restaurar para pruebas usa primero otra base y jamás sobrescribe automáticamente la existente.

## DT16 — Dependencias y operación sin Internet

**Estado:** aceptada.

Iconos, estilos y fuentes usados por la aplicación se sirven localmente; no hay CDN, analítica ni API externa declarada en el código. El repositorio incluye Playwright y suites pública/privada que usan el canal `msedge` instalado en el equipo, no un navegador empaquetado. Tras obtener las dependencias, el runtime **debe** funcionar sin Internet con API y SQL Server activos, pero ese objetivo continúa Pendiente hasta ejecutar PA26/PA32 en una copia limpia y desconectada.
