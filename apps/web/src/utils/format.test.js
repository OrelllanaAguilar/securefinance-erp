import { describe, expect, it } from 'vitest';
import { embeddedList, firstDefined, formatMoney, normalizeList } from './format.js';

describe('formatMoney', () => {
  it('mantiene exacto un DECIMAL(19,2) sin convertirlo a Number', () => {
    expect(formatMoney('99999999999999999.99')).toBe('GTQ\u00a099,999,999,999,999,999.99');
  });

  it('conserva importes contables pequeños y dos decimales', () => {
    expect(formatMoney('0.05')).toBe('GTQ\u00a00.05');
    expect(formatMoney('112.00')).toBe('GTQ\u00a0112.00');
  });

  it('no presenta un dato inválido como un importe válido', () => {
    expect(formatMoney('1.234')).toBe('1.234 GTQ');
  });
});

describe('normalización de respuestas', () => {
  it('acepta listas directas y contenedores comunes', () => {
    expect(normalizeList([{ id: 1 }])).toEqual([{ id: 1 }]);
    expect(normalizeList({ items: [{ id: 2 }] })).toEqual([{ id: 2 }]);
  });

  it('interpreta listas JSON generadas por SQL Server', () => {
    expect(embeddedList('[{"id":1,"name":"Cajero"}]')).toEqual([{ id: 1, name: 'Cajero' }]);
    expect(embeddedList('no-json')).toEqual([]);
  });

  it('selecciona la primera clave definida sin perder cero', () => {
    expect(firstDefined({ total: 0 }, ['total'], 'x')).toBe(0);
  });
});
