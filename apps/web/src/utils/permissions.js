export const PERMISSIONS = Object.freeze({
  SELL: 'VENTAS_CREAR',
  AUDIT: 'AUDITORIA_LEER',
  ROLES: 'ROLES_GESTIONAR',
  PRODUCTS: 'PRODUCTOS_GESTIONAR',
  CUSTOMERS: 'CLIENTES_GESTIONAR',
  REPORTS: 'REPORTES_LEER',
  USERS: 'USUARIOS_GESTIONAR',
});

export function permissionSet(user) {
  const values = user?.permissions || user?.permisos || [];
  return new Set(values.map((item) => (typeof item === 'string' ? item : item.code || item.codigo)));
}

export function hasPermission(user, required) {
  if (!required || (Array.isArray(required) && required.length === 0)) return true;
  const current = permissionSet(user);
  const expected = Array.isArray(required) ? required : [required];
  return expected.some((permission) => current.has(permission));
}

export function canReadSales(user) {
  return hasPermission(user, [PERMISSIONS.SELL, PERMISSIONS.REPORTS]);
}

export function canReadCatalogs(user) {
  return hasPermission(user, [PERMISSIONS.SELL, PERMISSIONS.PRODUCTS, PERMISSIONS.CUSTOMERS]);
}
