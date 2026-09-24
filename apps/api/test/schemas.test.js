import { describe, expect, it } from 'vitest';
import { parseBigIntId, parseId } from '../src/lib/schemas.js';

describe('identificadores de ruta', () => {
  it('mantiene los identificadores int para catálogos', () => {
    expect(parseId({ id: '2147483647' })).toBe(2147483647);
    expect(() => parseId({ id: '2147483648' })).toThrow();
  });

  it('acepta todo el rango positivo de BIGINT sin perder precisión', () => {
    expect(parseBigIntId({ id: '9223372036854775807' })).toBe(9223372036854775807n);
    expect(() => parseBigIntId({ id: '9223372036854775808' })).toThrow();
    expect(() => parseBigIntId({ id: '01' })).toThrow();
  });
});
