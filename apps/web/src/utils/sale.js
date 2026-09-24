import { ApiError } from '../api/client.js';

const CONFIRMED_STATUSES = new Set(['confirmed', 'confirmada', 'completed', 'completada', 'success', 'exitosa']);
const REJECTED_STATUSES = new Set(['rejected', 'rechazada', 'failed', 'fallida', 'cancelled', 'canceled', 'cancelada']);

export function classifySaleFailure(error) {
  if (!(error instanceof ApiError)) return 'unknown';
  if (error.code === 'INVALID_RESPONSE' || error.status === 0 || error.status >= 500) return 'unknown';
  return 'rejected';
}

export function saleResultOutcome(result = {}) {
  const saleId = result.id ?? result.saleId ?? result.invoiceId ?? result.facturaId;
  const status = String(result.status ?? result.estado ?? '').trim().toLowerCase();
  if (saleId !== undefined && saleId !== null && saleId !== '') return { outcome: 'confirmed', saleId };
  if (CONFIRMED_STATUSES.has(status)) return { outcome: 'confirmed', saleId: null };
  if (REJECTED_STATUSES.has(status)) return { outcome: 'rejected', saleId: null };
  return { outcome: 'pending', saleId: null };
}
