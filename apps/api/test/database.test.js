import { beforeEach, describe, expect, it, vi } from 'vitest';

const driver = vi.hoisted(() => ({
  configs: [],
  requestOptions: [],
  procedures: [],
}));

vi.mock('mssql', () => ({
  default: {
    ConnectionPool: class FakeConnectionPool {
      constructor(config) {
        // The real driver normalizes this object in place.
        config.port ??= 1433;
        driver.configs.push(config);
      }

      on() {}

      async connect() {
        return this;
      }

      request(options) {
        driver.requestOptions.push(options);
        const request = {
          input: vi.fn(() => request),
          output: vi.fn(() => request),
          execute: vi.fn(async (procedure) => {
            driver.procedures.push(procedure);
            return { recordsets: [[{ ok: true }]] };
          }),
        };
        return request;
      }

      async close() {}
    },
  },
}));

import { SqlDatabase } from '../src/db/database.js';

describe('SqlDatabase', () => {
  beforeEach(() => {
    driver.configs.length = 0;
    driver.requestOptions.length = 0;
    driver.procedures.length = 0;
  });

  it('entrega al driver una copia mutable sin alterar la configuración congelada', async () => {
    const config = Object.freeze({
      server: '127.0.0.1',
      database: 'SecureFinanceERP_Test',
      options: Object.freeze({ encrypt: false }),
      pool: Object.freeze({ max: 1 }),
    });
    const database = new SqlDatabase(config);

    await database.connect();

    expect(config).not.toHaveProperty('port');
    expect(driver.configs[0]).not.toBe(config);
    expect(driver.configs[0]).toMatchObject({ port: 1433, options: { encrypt: false }, pool: { max: 1 } });
  });

  it('usa el override requestTimeout soportado por mssql', async () => {
    const database = new SqlDatabase({ server: '127.0.0.1', database: 'SecureFinanceERP_Test' });

    await database.execute('dbo.sp_ProcesarVentaTransaccional', {}, { timeout: 30000 });

    expect(driver.requestOptions).toEqual([{ requestTimeout: 30000 }]);
    expect(driver.procedures).toEqual(['dbo.sp_ProcesarVentaTransaccional']);
  });
});
