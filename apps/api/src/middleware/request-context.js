import crypto from 'node:crypto';

const correlationPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function requestContext(request, response, next) {
  const proposed = request.get('x-correlation-id');
  request.correlationId = correlationPattern.test(proposed ?? '') ? proposed : crypto.randomUUID();
  response.set('x-correlation-id', request.correlationId);
  next();
}
