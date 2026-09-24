import { describe, expect, it } from 'vitest';
import { hasPermission, permissionSet, PERMISSIONS } from './permissions.js';

describe('permisos efectivos', () => {
  it('acepta códigos devueltos como cadenas u objetos', () => {
    expect(permissionSet({ permissions: ['VENTAS_CREAR', { code: 'REPORTES_LEER' }] })).toEqual(new Set(['VENTAS_CREAR', 'REPORTES_LEER']));
  });

  it('requiere al menos uno de los permisos solicitados', () => {
    const user = { permissions: [PERMISSIONS.REPORTS] };
    expect(hasPermission(user, [PERMISSIONS.SELL, PERMISSIONS.REPORTS])).toBe(true);
    expect(hasPermission(user, PERMISSIONS.USERS)).toBe(false);
  });

  it('no concede ventas por el nombre del rol administrador', () => {
    expect(hasPermission({ roles: ['Administrador'], permissions: [] }, PERMISSIONS.SELL)).toBe(false);
  });
});
