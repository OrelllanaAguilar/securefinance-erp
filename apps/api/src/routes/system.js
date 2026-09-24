import { Router } from 'express';
import { asyncHandler } from '../lib/async-handler.js';

export function createAdminHealthRouter() {
  const router = Router();
  router.get(
    '/',
    asyncHandler(async (request, response) => {
      const result = await request.app.locals.database.execute('dbo.sp_VerificarEstado');
      response.json({
        data: {
          status: 'available',
          database: result.recordsets?.[0]?.[0]?.databaseStatus ?? 'available',
          checkedAt: new Date().toISOString(),
        },
      });
    }),
  );
  return router;
}
