import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const validEnvironment = {
  DB_SERVER: '127.0.0.1',
  DB_PORT: '1433',
  DB_NAME: 'SecureFinanceERP_Test',
  DB_USER: 'SecureFinanceApi',
  DB_PASSWORD: 'Private-Database-Password-42!',
  CSRF_SECRET: 'csrf-private-value-with-more-than-32-characters',
};

describe('loadConfig', () => {
  it('acepta secretos privados y conserva inmutable la configuración pública', () => {
    const config = loadConfig(validEnvironment);

    expect(config.database.password).toBe(validEnvironment.DB_PASSWORD);
    expect(Object.isFrozen(config)).toBe(true);
    expect(Object.isFrozen(config.database)).toBe(true);
  });

  it.each([
    ['DB_PASSWORD', 'replace-with-a-private-random-password'],
    ['CSRF_SECRET', 'replace-with-at-least-32-random-characters'],
  ])('rechaza el marcador de ejemplo en %s', (field, value) => {
    expect(() => loadConfig({ ...validEnvironment, [field]: value })).toThrow(/marcador de \.env\.example/u);
  });

  it('normaliza la barra final de los orígenes antes de compararlos', () => {
    const config = loadConfig({
      ...validEnvironment,
      APP_ORIGIN: 'http://127.0.0.1:3000/',
      DEV_ORIGIN: 'http://localhost:5173/',
    });

    expect(config.appOrigin).toBe('http://127.0.0.1:3000');
    expect(config.allowedOrigins).toEqual([
      'http://127.0.0.1:3000',
      'http://localhost:5173',
    ]);
  });
});
