import { Router } from 'express';
import { z } from 'zod';
import { sql, input } from '../db/database.js';
import { asyncHandler } from '../lib/async-handler.js';
import { pageParameters } from '../lib/parameters.js';
import { listResult } from '../lib/result.js';
import { dateSchema } from '../lib/schemas.js';
import {
  authenticate,
  requirePermission,
  sessionParameters,
} from '../middleware/session.js';

const reportQuerySchema = z
  .object({
    from: dateSchema,
    to: dateSchema,
    page: z.coerce.number().int().positive().default(1),
    pageSize: z.enum(['10', '25', '50']).default('25').transform(Number),
    search: z.string().max(160).default(''),
    sort: z.enum(['date', 'number', 'customer', 'cashier', 'total']).default('date'),
    direction: z.enum(['asc', 'desc']).default('desc'),
  })
  .strict()
  .superRefine((query, context) => {
    const start = Date.parse(`${query.from}T00:00:00Z`);
    const end = Date.parse(`${query.to}T00:00:00Z`);
    const days = (end - start) / 86400000;
    if (!Number.isFinite(days) || days < 0 || days > 365) {
      context.addIssue({
        code: 'custom',
        path: ['to'],
        message: 'El intervalo debe contener entre 1 y 366 días inclusivos.',
      });
    }
  });

export function createReportsRouter() {
  const router = Router();
  router.get(
    '/sales',
    authenticate(),
    requirePermission('REPORTES_LEER'),
    asyncHandler(async (request, response) => {
      const query = reportQuerySchema.parse(request.query);
      const result = await request.app.locals.database.execute('dbo.sp_ObtenerHistoricoVentas', {
        ...sessionParameters(request),
        FechaDesde: input(sql.VarChar(10), query.from),
        FechaHasta: input(sql.VarChar(10), query.to),
        ...pageParameters(query),
      });
      const payload = listResult(result);
      payload.meta.totals = result.recordsets?.[2]?.[0] ?? null;
      payload.meta.range = { from: query.from, to: query.to };
      response.json(payload);
    }),
  );
  return router;
}
