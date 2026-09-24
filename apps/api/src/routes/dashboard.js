import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler.js';
import { authenticate, sessionParameters } from '../middleware/session.js';

export function createDashboardRouter() {
  const router = Router();
  router.get(
    '/',
    authenticate(),
    asyncHandler(async (request, response) => {
      const result = await request.app.locals.database.execute('dbo.sp_ObtenerResumenInicio', {
        ...sessionParameters(request),
      });
      response.json({
        data: {
          summary: result.recordsets?.[0]?.[0] ?? null,
          shortcuts: result.recordsets?.[1] ?? [],
          refreshedAt: new Date().toISOString(),
        },
      });
    }),
  );
  return router;
}
