import { describe, expect, it, vi } from 'vitest';
import { ApiError, request, setCsrfToken } from './client.js';

function jsonResponse(payload, status = 200, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });
}

describe('cliente HTTP', () => {
  it('envía cookies, JSON y CSRF únicamente por la capa común', async () => {
    setCsrfToken('csrf-prueba');
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse({ data: { id: 7 } }));
    await request('/api/test', { method: 'POST', body: { name: 'Dato' } });
    const [, options] = fetchMock.mock.calls[0];
    expect(options.credentials).toBe('include');
    expect(options.headers.get('x-csrf-token')).toBe('csrf-prueba');
    expect(options.body).toBe('{"name":"Dato"}');
  });

  it('conserva código, campos y correlación de errores públicos', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse({ error: { code: 'VERSION_CONFLICT', message: 'Cambió el registro.', fields: { version: 'Obsoleta' } }, correlationId: 'corr-1' }, 409));
    await expect(request('/api/test')).rejects.toMatchObject({
      name: 'ApiError', status: 409, code: 'VERSION_CONFLICT', correlationId: 'corr-1', fields: { version: 'Obsoleta' },
    });
  });

  it('distingue un fallo de red de una respuesta vacía', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new TypeError('offline'));
    await expect(request('/api/test')).rejects.toBeInstanceOf(ApiError);
    await expect(request('/api/test')).rejects.toMatchObject({ status: 0, code: 'NETWORK_ERROR' });
  });
});
