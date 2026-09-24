import sql from 'mssql';
import { fromDatabaseError } from '../lib/api-error.js';

export { sql };

export class SqlDatabase {
  #config;
  #pool;

  constructor(config) {
    this.#config = config;
  }

  async connect() {
    if (!this.#pool) {
      // `mssql` normalizes its configuration in place (for example, `port`).
      // Keep the application configuration immutable and give the driver its
      // own mutable copy instead.
      const pool = new sql.ConnectionPool(structuredClone(this.#config));
      pool.on('error', (error) => {
        console.error('El pool de SQL Server informó un error.', {
          code: error.code,
          name: error.name,
        });
      });
      this.#pool = pool.connect().catch((error) => {
        this.#pool = undefined;
        throw fromDatabaseError(error);
      });
    }
    return this.#pool;
  }

  async execute(procedure, parameters = {}, options = {}) {
    try {
      const pool = await this.connect();
      const request = pool.request(
        options.timeout === undefined ? undefined : { requestTimeout: options.timeout },
      );
      for (const [name, parameter] of Object.entries(parameters)) {
        if (parameter.table) {
          request.input(name, parameter.value);
          continue;
        }
        if (parameter.output) {
          request.output(name, parameter.type, parameter.value);
        } else {
          request.input(name, parameter.type, parameter.value);
        }
      }
      return await request.execute(procedure);
    } catch (error) {
      if (error?.name === 'ApiError') throw error;
      throw fromDatabaseError(error);
    }
  }

  async close() {
    if (!this.#pool) return;
    try {
      const pool = await this.#pool;
      await pool.close();
    } finally {
      this.#pool = undefined;
    }
  }
}

export const input = (type, value) => ({ type, value });
export const inputTable = (value) => ({ table: true, value });
