import { sql, input } from '../db/database.js';
import { ApiError } from '../lib/api-error.js';
import { clientIp, csrfToken, safeEqualText, tokenDigest } from '../lib/security.js';

function normalizeSession(result) {
  const row = result.recordsets?.[0]?.[0];
  if (!row) throw new ApiError(401, 'SESSION_INVALID', 'La sesión no existe o ha vencido.');
  const permissions = (result.recordsets?.[1] ?? []).map((item) => item.code);
  const roles = (result.recordsets?.[2] ?? []).map((item) => item.name);
  return {
    id: row.userId,
    username: row.username,
    displayName: row.displayName,
    email: row.email,
    mustChangePassword: Boolean(row.mustChangePassword),
    theme: row.theme,
    version: row.version,
    sessionExpiresAt: row.sessionExpiresAt,
    absoluteExpiresAt: row.absoluteExpiresAt,
    permissions,
    roles,
  };
}

export function authenticate({ touch = true, allowPasswordChangeOnly = false } = {}) {
  return async function sessionMiddleware(request, _response, next) {
    try {
      const config = request.app.locals.config;
      const rawToken = request.cookies?.[config.cookie.name];
      if (!rawToken) {
        throw new ApiError(401, 'SESSION_REQUIRED', 'Debe iniciar sesión.');
      }
      const result = await request.app.locals.database.execute('dbo.sp_ValidarSesionApi', {
        SesionHash: input(sql.VarBinary(64), tokenDigest(rawToken)),
        DireccionIP: input(sql.VarChar(45), clientIp(request)),
        ActualizarActividad: input(sql.Bit, touch),
        CorrelationId: input(sql.UniqueIdentifier, request.correlationId),
      });
      request.sessionToken = rawToken;
      request.sessionHash = tokenDigest(rawToken);
      request.user = normalizeSession(result);
      if (request.user.mustChangePassword && !allowPasswordChangeOnly) {
        throw new ApiError(
          403,
          'PASSWORD_CHANGE_REQUIRED',
          'Debe cambiar la contraseña antes de continuar.',
        );
      }
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireCsrf(request, _response, next) {
  const config = request.app.locals.config;
  const supplied = request.get('x-csrf-token');
  const expected = request.sessionToken
    ? csrfToken(request.sessionToken, config.csrfSecret)
    : undefined;
  if (!safeEqualText(supplied, expected)) {
    return next(new ApiError(403, 'CSRF_INVALID', 'La verificación de la solicitud no es válida.'));
  }
  next();
}

export function requirePermission(...acceptedPermissions) {
  return function permissionMiddleware(request, _response, next) {
    const available = new Set(request.user?.permissions ?? []);
    if (!acceptedPermissions.some((permission) => available.has(permission))) {
      return next(new ApiError(403, 'FORBIDDEN', 'No tiene permiso para realizar esta operación.'));
    }
    next();
  };
}

export function sessionParameters(request) {
  return {
    SesionHash: input(sql.VarBinary(64), request.sessionHash),
    DireccionIP: input(sql.VarChar(45), clientIp(request)),
    CorrelationId: input(sql.UniqueIdentifier, request.correlationId),
  };
}

export { normalizeSession };
