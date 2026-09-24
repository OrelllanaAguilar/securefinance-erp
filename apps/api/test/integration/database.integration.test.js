import sql from 'mssql';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { SqlDatabase } from '../../src/db/database.js';

const enabled = process.env.RUN_SQL_INTEGRATION === 'true';

describe.skipIf(!enabled)('SQL Server con la identidad real de la API', () => {
  let config;
  let database;
  let directPool;

  beforeAll(async () => {
    config = loadConfig();
    database = new SqlDatabase(config.database);
    await database.connect();
    directPool = await new sql.ConnectionPool(structuredClone(config.database)).connect();
  });

  afterAll(async () => {
    await Promise.allSettled([database?.close(), directPool?.close()]);
  });

  it('ejecuta únicamente el procedimiento de estado autorizado', async () => {
    const result = await database.execute('dbo.sp_VerificarEstado');
    expect(result.recordsets[0][0]).toMatchObject({
      databaseStatus: 'available',
      currency: 'GTQ',
      timeZone: 'America/Guatemala',
    });
  });

  it('deniega lectura y escritura directa sobre tablas de negocio', async () => {
    for (const statement of [
      'SELECT TOP (1) UsuarioId FROM dbo.Usuario;',
      "UPDATE dbo.ConfiguracionSistema SET MonedaCodigo='USD' WHERE ConfiguracionId=1;",
    ]) {
      await expect(directPool.request().query(statement)).rejects.toMatchObject({ number: 229 });
    }
  });

  it('deniega ejecutar procedimientos internos no concedidos', async () => {
    await expect(directPool.request().execute('dbo.sp_LimpiarContextoAuditoria')).rejects.toMatchObject({
      number: 229,
    });
  });
});
