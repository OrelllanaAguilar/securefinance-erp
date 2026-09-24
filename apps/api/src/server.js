import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { SqlDatabase } from './db/database.js';

const config = loadConfig();
const database = new SqlDatabase(config.database);

try {
  await database.connect();
  const health = await database.execute('dbo.sp_VerificarEstado');
  const databaseLocale = health.recordsets?.[0]?.[0];
  if (
    databaseLocale?.currency !== config.currencyCode
    || databaseLocale?.timeZone !== config.timeZone
  ) {
    throw new Error('La moneda o zona horaria de la API no coincide con ConfiguracionSistema.');
  }
} catch (error) {
  console.error('No se pudo conectar con SQL Server al iniciar.', {
    code: error.code,
    message: error.message,
  });
  process.exitCode = 1;
  throw error;
}

const app = createApp({ config, database });
const server = app.listen(config.port, config.host, () => {
  console.info(`SecureFinance ERP escucha en ${config.appOrigin}.`);
});

async function shutdown(signal) {
  console.info(`Cierre solicitado por ${signal}.`);
  server.close(async () => {
    await database.close();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
