import { Router } from 'express';
import { z } from 'zod';
import { sql, input } from '../db/database.js';
import { asyncHandler } from '../lib/async-handler.js';
import { firstRow } from '../lib/result.js';
import { passwordSchema, themeSchema } from '../lib/schemas.js';
import { authenticate, requireCsrf, sessionParameters } from '../middleware/session.js';

const preferenceSchema = z.object({ theme: themeSchema }).strict();
const passwordChangeSchema = z
  .object({
    currentPassword: z.string().min(1).max(128),
    newPassword: passwordSchema,
  })
  .strict();

export function createMeRouter() {
  const router = Router();

  router.get(
    '/',
    authenticate(),
    asyncHandler(async (request, response) => {
      const result = await request.app.locals.database.execute('dbo.sp_ConsultarPerfil', {
        ...sessionParameters(request),
      });
      response.json({
        data: {
          ...(firstRow(result) ?? {}),
          permissions: result.recordsets?.[1] ?? [],
          roles: result.recordsets?.[2] ?? [],
        },
      });
    }),
  );

  router.get(
    '/preferences',
    authenticate({ touch: false }),
    asyncHandler(async (request, response) => {
      const result = await request.app.locals.database.execute(
        'dbo.sp_ObtenerPreferenciasUsuario',
        { ...sessionParameters(request) },
      );
      response.json({ data: firstRow(result) });
    }),
  );

  router.put(
    '/preferences',
    authenticate(),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = preferenceSchema.parse(request.body);
      const result = await request.app.locals.database.execute(
        'dbo.sp_GuardarPreferenciasUsuario',
        {
          ...sessionParameters(request),
          Tema: input(sql.VarChar(10), body.theme),
        },
      );
      response.json({ data: firstRow(result) });
    }),
  );

  router.put(
    '/password',
    authenticate({ allowPasswordChangeOnly: true }),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = passwordChangeSchema.parse(request.body);
      const config = request.app.locals.config;
      await request.app.locals.database.execute('dbo.sp_CambiarPassword', {
        ...sessionParameters(request),
        ContrasenaActual: input(sql.NVarChar(128), body.currentPassword),
        ContrasenaNueva: input(sql.NVarChar(128), body.newPassword),
      });
      response.clearCookie(config.cookie.name, {
        httpOnly: config.cookie.httpOnly,
        secure: config.cookie.secure,
        sameSite: config.cookie.sameSite,
        path: config.cookie.path,
      });
      response.json({ data: { message: 'Contraseña actualizada. Inicie sesión de nuevo.' } });
    }),
  );

  return router;
}
