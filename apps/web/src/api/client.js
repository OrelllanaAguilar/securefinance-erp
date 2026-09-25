let csrfToken = null;

export class ApiError extends Error {
  constructor(message, { status = 0, code = 'NETWORK_ERROR', fields = null, correlationId = null, cause } = {}) {
    super(message, { cause });
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.fields = fields;
    this.correlationId = correlationId;
  }
}

export function setCsrfToken(value) {
  csrfToken = value || null;
}

export function getCsrfToken() {
  return csrfToken;
}

export function buildQuery(values = {}) {
  const query = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') query.set(key, String(value));
  });
  const suffix = query.toString();
  return suffix ? `?${suffix}` : '';
}

export async function request(path, options = {}) {
  const method = (options.method || 'GET').toUpperCase();
  const timeoutMs = options.timeoutMs ?? 30_000;
  const headers = new Headers(options.headers);
  headers.set('Accept', 'application/json');
  if (options.body !== undefined) headers.set('Content-Type', 'application/json');
  if (!['GET', 'HEAD', 'OPTIONS'].includes(method) && csrfToken) headers.set('x-csrf-token', csrfToken);

  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);
  const suppliedSignal = options.signal;
  const forwardAbort = () => controller.abort(suppliedSignal.reason);
  if (suppliedSignal?.aborted) forwardAbort();
  else suppliedSignal?.addEventListener('abort', forwardAbort, { once: true });

  let response;
  try {
    response = await fetch(path, {
      ...options,
      method,
      credentials: 'include',
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: controller.signal,
    });
  } catch (cause) {
    if (timedOut) {
      throw new ApiError('La solicitud tardó demasiado. Comprueba la API y vuelve a intentarlo.', {
        code: 'REQUEST_TIMEOUT',
        cause,
      });
    }
    if (suppliedSignal?.aborted || cause?.name === 'AbortError') throw cause;
    throw new ApiError('No se pudo conectar con el servicio. Comprueba que la API esté activa.', { cause });
  } finally {
    clearTimeout(timeout);
    suppliedSignal?.removeEventListener('abort', forwardAbort);
  }

  const contentType = response.headers.get('content-type') || '';
  let payload = null;
  if (response.status !== 204 && contentType.includes('application/json')) {
    try {
      payload = await response.json();
    } catch (cause) {
      throw new ApiError('El servicio devolvió una respuesta que no se pudo interpretar.', {
        status: response.status,
        code: 'INVALID_RESPONSE',
        cause,
      });
    }
  }

  const nextToken = payload?.data?.csrfToken || payload?.csrfToken;
  if (nextToken) setCsrfToken(nextToken);

  if (!response.ok) {
    const details = payload?.error || {};
    const error = new ApiError(details.message || publicStatusMessage(response.status), {
      status: response.status,
      code: details.code || `HTTP_${response.status}`,
      fields: details.fields,
      correlationId: payload?.correlationId || response.headers.get('x-correlation-id'),
    });
    if (response.status === 401) window.dispatchEvent(new CustomEvent('securefinance:unauthorized', { detail: error }));
    throw error;
  }

  return payload || { data: null };
}

function publicStatusMessage(status) {
  const messages = {
    400: 'Revisa los datos enviados.',
    401: 'Tu sesión terminó. Vuelve a iniciar sesión.',
    403: 'No tienes permiso para realizar esta acción.',
    404: 'No se encontró el recurso solicitado.',
    409: 'La información cambió. Actualiza y vuelve a intentarlo.',
    429: 'Hay demasiados intentos. Espera antes de volver a probar.',
    503: 'El servicio no está disponible temporalmente.',
  };
  return messages[status] || 'Ocurrió un error al procesar la solicitud.';
}

export function errorMessage(error) {
  if (!(error instanceof ApiError)) return 'Ocurrió un error inesperado.';
  return error.correlationId ? `${error.message} Referencia: ${error.correlationId}.` : error.message;
}
