# SecureFinance ERP

Aplicación web local académica para ventas, inventario, clientes, usuarios, roles, reportes y auditoría. Usa React 19 + Vite 8, Express 5, Node.js 24, `mssql` y Microsoft SQL Server. La interfaz nunca accede directamente a la base: la API llama procedimientos almacenados con parámetros tipados.

La implementación sigue los 14 casos de uso de la especificación v2.0. No se presenta como certificación de seguridad ni como sistema listo para producción: el hash SHA2-512 con salt individual es el perfil exigido por la rúbrica y debería migrarse a un verificador con factor de trabajo antes de una publicación real.

## Requisitos

- Windows 11 y PowerShell 7 o Windows PowerShell 5.1.
- Node.js `24.18.x`, pnpm `10.34.4` y conexión a internet solo para instalar dependencias.
- SQL Server 2022 o 2025 y `sqlcmd`. SQL Server Express es compatible; no se presupone SQL Server Agent.
- Una instancia accesible localmente. Los valores de ejemplo usan `.\SQLEXPRESS` para administración y TCP `127.0.0.1:1433` para la cuenta de la API.

## Instalación reproducible

Desde la raíz del proyecto:

```powershell
corepack enable
pnpm install --frozen-lockfile

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-Database.ps1 `
  -AdminServerInstance '.\SQLEXPRESS' `
  -DatabaseName 'SecureFinanceERP' `
  -ApiLoginName 'SecureFinanceApi'

pnpm build
pnpm start
```

Abra `http://127.0.0.1:3000`. El instalador:

1. crea o actualiza objetos sin borrar una base ni datos existentes;
2. aprovisiona el login SQL de privilegio mínimo;
3. crea el primer administrador si no existe;
4. escribe `.env` y `secrets/first-access.txt` e intenta restringir sus ACL al usuario actual; si Windows no permite aplicarlas, muestra una advertencia que debe resolverse antes de usar las credenciales.

Lea la credencial inicial solo desde ese archivo privado, inicie sesión y cambie la contraseña obligatoria. Después elimine el archivo de primer acceso. Los secretos, el buzón local, respaldos y evidencia de ejecución están excluidos del repositorio.

Para una base demostrativa aislada use un nombre terminado en `_Test` y `-IncludeDemoData`. La semilla se niega a operar en otros nombres:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-Database.ps1 `
  -DatabaseName 'SecureFinanceERP_Demo_Test' `
  -ApiLoginName 'SecureFinanceApiDemo' `
  -IncludeDemoData
```

El script se niega a tocar una base existente salvo que se indique `-AllowExisting`; en ese caso exige recibir la contraseña SQL como `SecureString` y no restablece silenciosamente la clave de una cuenta bootstrap existente. Consulte [database/README.md](database/README.md) para la instalación administrativa manual y migraciones.

## Desarrollo y operación

```powershell
pnpm dev                 # API 127.0.0.1:3000 + Vite 127.0.0.1:5173
pnpm build               # frontend para un único origen
pnpm start               # Express sirve API y frontend compilado
pnpm lint
pnpm test
pnpm sql:verify          # comprueba el acceso mínimo usando .env
$env:RUN_SQL_INTEGRATION='true'; pnpm test:integration; Remove-Item Env:RUN_SQL_INTEGRATION
pnpm test:smoke          # solo contra una base *_Test y con la API activa
pnpm test:e2e
pnpm test:e2e:private    # requiere el humo real previo y una base *_Test
pnpm docs:pdf
```

`pnpm start` está diseñado para funcionar sin Internet después de instalar dependencias: no hay CDN, telemetría ni servicios externos. La comprobación completa de desconexión y reinicio corresponde a PA26/PA32 y no se presume por diseño. El servidor se enlaza únicamente a loopback; para HTTPS local deben ajustarse `APP_ORIGIN` y `COOKIE_SECURE=true` detrás de un terminador local confiable.

## Estructura

- `apps/web`: SPA en español, temas Claro/Oscuro/Sistema y rutas UC01–UC14.
- `apps/api`: API de mismo origen, cookie HttpOnly, CSRF, sesión opaca y validación estricta.
- `database`: esquema, funciones, procedimientos, triggers, permisos, aprovisionamiento y pruebas SQL.
- `tests`: instrucciones y pruebas de integración/interfaz.
- `docs`: arquitectura, ERD, contratos, trazabilidad, manual, respaldo y matriz PA01–PA32.

La matriz comienza en `Pendiente`. Solo debe cambiarse con fecha, entorno, datos, resultado observado y evidencia real; leer código o aprobar pruebas unitarias no demuestra ACID, concurrencia, restauración ni los objetivos QC01–QC08.

## Documentación clave

- [Arquitectura](docs/architecture.md)
- [Modelo físico](docs/physical-erd.md)
- [Contratos API](docs/api-contracts.md)
- [Procedimientos almacenados](docs/stored-procedures.md)
- [Trazabilidad UC → ruta → API → SQL → PA](docs/traceability.md)
- [Manual de usuario](docs/user-manual.md)
- [Matriz de pruebas](docs/test-matrix.md)
- [Verificación técnica ejecutada](docs/verification-results.md)
- [Respaldo y restauración](docs/backup-restore.md)
- [Guion de demostración](docs/demo-script.md)
