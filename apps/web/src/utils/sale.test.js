import { describe, expect, it } from 'vitest';
import { ApiError } from '../api/client.js';
import { classifySaleFailure, saleResultOutcome } from './sale.js';

describe('resultado de una venta idempotente', () => {
  it('conserva la clave ante fallos ambiguos, incluso una respuesta 2xx ilegible', () => {
    expect(classifySaleFailure(new ApiError('Sin red'))).toBe('unknown');
    expect(classifySaleFailure(new ApiError('Respuesta ilegible', { status: 201, code: 'INVALID_RESPONSE' }))).toBe('unknown');
    expect(classifySaleFailure(new ApiError('Servicio caído', { status: 503 }))).toBe('unknown');
  });

  it('permite una nueva clave únicamente tras un rechazo HTTP concluyente', () => {
    expect(classifySaleFailure(new ApiError('Datos inválidos', { status: 400, code: 'VALIDATION' }))).toBe('rejected');
    expect(classifySaleFailure(new ApiError('Conflicto', { status: 409, code: 'STOCK_CONFLICT' }))).toBe('rejected');
  });

  it('distingue confirmación, rechazo y espera al consultar la misma clave', () => {
    expect(saleResultOutcome({ saleId: '42', status: 'pending' })).toEqual({ outcome: 'confirmed', saleId: '42' });
    expect(saleResultOutcome({ estado: 'RECHAZADA' })).toEqual({ outcome: 'rejected', saleId: null });
    expect(saleResultOutcome({ status: 'pending' })).toEqual({ outcome: 'pending', saleId: null });
  });
});
