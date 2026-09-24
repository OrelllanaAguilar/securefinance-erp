import { describe, expect, it } from 'vitest';
import { csrfToken, safeEqualText, temporaryPassword, tokenDigest } from '../src/lib/security.js';

describe('primitivas locales de seguridad', () => {
  it('genera digest SHA-512 de 64 bytes', () => {
    expect(tokenDigest('token-opaco')).toHaveLength(64);
  });

  it('deriva CSRF estable por sesión y secreto', () => {
    const first = csrfToken('sesion', 'x'.repeat(32));
    const second = csrfToken('sesion', 'x'.repeat(32));
    expect(safeEqualText(first, second)).toBe(true);
    expect(safeEqualText(first, `${second}x`)).toBe(false);
  });

  it('crea una clave temporal que satisface la política académica', () => {
    const password = temporaryPassword();
    expect(password.length).toBeGreaterThanOrEqual(12);
    expect(password).toMatch(/[A-Z]/);
    expect(password).toMatch(/[a-z]/);
    expect(password).toMatch(/[0-9]/);
    expect(password).toMatch(/[^A-Za-z0-9]/);
  });
});
