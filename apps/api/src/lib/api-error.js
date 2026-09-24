export class ApiError extends Error {
  constructor(status, code, message, options = {}) {
    super(message, { cause: options.cause });
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.fields = options.fields;
    this.details = options.details;
  }
}

const sqlErrorMap = new Map([
  [51001, [401, 'SESSION_INVALID', 'La sesión no existe o ha vencido.']],
  [51002, [403, 'FORBIDDEN', 'No tiene permiso para realizar esta operación.']],
  [51003, [404, 'NOT_FOUND', 'El recurso solicitado no existe.']],
  [51004, [409, 'CONFLICT', 'La operación entra en conflicto con datos vigentes.']],
  [51005, [429, 'RATE_LIMITED', 'Demasiados intentos. Inténtelo más tarde.']],
  [51006, [400, 'VALIDATION_ERROR', 'Los datos enviados no son válidos.']],
  [51007, [403, 'PASSWORD_CHANGE_REQUIRED', 'Debe cambiar la contraseña antes de continuar.']],
  [51008, [409, 'IDEMPOTENCY_CONFLICT', 'La clave de idempotencia ya fue usada con otro contenido.']],
  [51009, [409, 'STALE_VERSION', 'Otro usuario modificó el registro. Actualice los datos.']],
  [51010, [409, 'INSUFFICIENT_STOCK', 'No hay existencias suficientes para completar la venta.']],
  [51011, [400, 'INVALID_CREDENTIALS', 'Usuario o contraseña incorrectos.']],
  [51012, [400, 'RESET_INVALID', 'El enlace no es válido o ya venció.']],
]);

function sqlNumber(error) {
  return (
    error?.number ??
    error?.originalError?.info?.number ??
    error?.precedingErrors?.find((item) => item?.number >= 51000)?.number
  );
}

export function fromDatabaseError(error) {
  const mapped = sqlErrorMap.get(sqlNumber(error));
  if (mapped) {
    return new ApiError(mapped[0], mapped[1], mapped[2], { cause: error });
  }

  const connectionCodes = new Set([
    'ECONNCLOSED',
    'ECONNREFUSED',
    'ELOGIN',
    'ETIMEOUT',
    'ESOCKET',
    'ENOTOPEN',
  ]);
  if (connectionCodes.has(error?.code) || error?.name === 'ConnectionError') {
    return new ApiError(
      503,
      'DATABASE_UNAVAILABLE',
      'El servicio de datos no está disponible en este momento.',
      { cause: error },
    );
  }

  return new ApiError(
    500,
    'INTERNAL_ERROR',
    'No fue posible completar la operación.',
    { cause: error },
  );
}
