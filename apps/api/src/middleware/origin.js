import { ApiError } from '../lib/api-error.js';

const safeMethods = new Set(['GET', 'HEAD', 'OPTIONS']);

export function sameOrigin(request, _response, next) {
  if (safeMethods.has(request.method)) return next();
  const origin = request.get('origin');
  if (origin && !request.app.locals.config.allowedOrigins.includes(origin)) {
    return next(new ApiError(403, 'ORIGIN_INVALID', 'El origen de la solicitud no está permitido.'));
  }
  next();
}
