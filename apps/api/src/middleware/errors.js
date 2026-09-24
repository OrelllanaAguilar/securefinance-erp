import { ZodError } from 'zod';
import { ApiError } from '../lib/api-error.js';

export function notFoundHandler(request, _response, next) {
  next(new ApiError(404, 'ROUTE_NOT_FOUND', `No existe la ruta ${request.method} ${request.path}.`));
}

export function errorHandler(error, request, response, _next) {
  let publicError = error;
  if (error instanceof SyntaxError && error.status === 400 && 'body' in error) {
    publicError = new ApiError(400, 'INVALID_JSON', 'El cuerpo JSON no es válido.');
  }
  if (error instanceof ZodError) {
    publicError = new ApiError(400, 'VALIDATION_ERROR', 'Revise los datos enviados.', {
      fields: error.issues.reduce((fields, issue) => {
        fields[issue.path.join('.')] = issue.message;
        return fields;
      }, {}),
    });
  }
  if (!(publicError instanceof ApiError)) {
    publicError = new ApiError(500, 'INTERNAL_ERROR', 'No fue posible completar la operación.', {
      cause: error,
    });
  }

  if (publicError.status >= 500) {
    console.error('Error de solicitud.', {
      correlationId: request.correlationId,
      code: error?.code,
      name: error?.name,
      message: error?.message,
    });
  }

  if (publicError.status === 401 && request.app.locals.config?.cookie) {
    const cookie = request.app.locals.config.cookie;
    response.clearCookie(cookie.name, {
      httpOnly: cookie.httpOnly,
      secure: cookie.secure,
      sameSite: cookie.sameSite,
      path: cookie.path,
    });
  }

  response.status(publicError.status).json({
    error: {
      code: publicError.code,
      message: publicError.message,
      ...(publicError.fields ? { fields: publicError.fields } : {}),
    },
    correlationId: request.correlationId,
  });
}
