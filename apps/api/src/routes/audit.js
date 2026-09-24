import { Router } from 'express';
import { z } from 'zod';
import { sql, input } from '../db/database.js';
import { asyncHandler } from '../lib/async-handler.js';
import { pageParameters } from '../lib/parameters.js';
import { listResult } from '../lib/result.js';
import {
  authenticate,
  requirePermission,
  sessionParameters,
} from '../middleware/session.js';

const procedures = Object.freeze({
  access: 'dbo.sp_ConsultarBitacoraAcceso',
  dml: 'dbo.sp_ConsultarAuditoriaDML',
  ddl: 'dbo.sp_ConsultarAuditoriaDDL',
});

const auditQuerySchema = z
  .object({
    page: z.coerce.number().int().positive().default(1),
    pageSize: z.enum(['10', '25', '50']).default('25').transform(Number),
    search: z.string().max(160).default(''),
    sort: z.enum(['date', 'actor', 'operation', 'object']).default('date'),
    direction: z.enum(['asc', 'desc']).default('desc'),
    from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  })
  .strict();

export function createAuditRouter() {
  const router = Router();
  router.get(
    '/:category',
    authenticate(),
    requirePermission('AUDITORIA_LEER'),
    asyncHandler(async (request, response) => {
      const category = z.enum(['access', 'dml', 'ddl']).parse(request.params.category);
      const query = auditQuerySchema.parse(request.query);
      const result = await request.app.locals.database.execute(procedures[category], {
        ...sessionParameters(request),
        ...pageParameters(query),
        FechaDesde: input(sql.VarChar(10), query.from ?? null),
        FechaHasta: input(sql.VarChar(10), query.to ?? null),
      });
      response.json(listResult(result));
    }),
  );
  return router;
}
