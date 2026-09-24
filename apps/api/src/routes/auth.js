import fs from 'node:fs/promises';
import path from 'node:path';
import { Router } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';
import { sql, input } from '../db/database.js';
import { ApiError } from '../lib/api-error.js';
import { asyncHandler } from '../lib/async-handler.js';
import { passwordSchema, usernameSchema } from '../lib/schemas.js';
import { csrfToken, randomToken, tokenDigest, clientIp } from '../lib/security.js';
import {
  authenticate,
  normalizeSession,
  requireCsrf,
  sessionParameters,
} from '../middleware/session.js';

const loginSchema = z
  .object({
    username: usernameSchema,
    password: z.string().min(1).max(128),
  })
  .strict();

const recoverSchema = z
  .object({ identity: z.string().min(3).max(254) })
  .strict();

const resetSchema = z
  .object({
    token: z.string().min(32).max(256),
    newPassword: passwordSchema,
  })
  .strict();

const publicRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 60,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  handler: (_request, _response, next) =>
    next(new ApiError(429, 'RATE_LIMITED', 'Demasiadas solicitudes. Inténtelo más tarde.')),
});

function cookieOptions(config) {
  return {
    httpOnly: config.cookie.httpOnly,
    secure: config.cookie.secure,
    sameSite: config.cookie.sameSite,
    path: config.cookie.path,
    maxAge: config.cookie.maxAge,
  };
}

async function deliverRecoveryMessage(config, delivery, rawToken, correlationId) {
  if (!delivery) return;
  const mailboxPath = path.resolve(config.mailboxPath);
  const relativeToWeb = path.relative(config.webDistPath, mailboxPath);
  if (relativeToWeb === '' || (!relativeToWeb.startsWith('..') && !path.isAbsolute(relativeToWeb))) {
    throw new Error('El buzón de recuperación no puede estar dentro del directorio web.');
  }
  await fs.mkdir(mailboxPath, { recursive: true, mode: 0o700 });
  const messagePath = path.join(mailboxPath, `${Date.now()}-${correlationId}.txt`);
  const url = new URL('/restablecer', config.appOrigin);
  url.searchParams.set('token', rawToken);
  const message = [
    'SecureFinance ERP — recuperación local',
    `Destinatario: ${delivery.mailboxAddress}`,
    `Caduca: ${delivery.expiresAt}`,
    `Enlace: ${url.toString()}`,
    '',
    'Este archivo es privado y no debe copiarse al directorio web ni al repositorio.',
  ].join('\n');
  await fs.writeFile(messagePath, message, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
}

export function createAuthRouter() {
  const router = Router();

  router.post(
    '/login',
    publicRateLimit,
    asyncHandler(async (request, response) => {
      const body = loginSchema.parse(request.body);
      const config = request.app.locals.config;
      const rawToken = randomToken();
      const result = await request.app.locals.database.execute('dbo.sp_AutenticarUsuario', {
        NombreUsuario: input(sql.VarChar(50), body.username),
        Contrasena: input(sql.NVarChar(128), body.password),
        SesionHash: input(sql.VarBinary(64), tokenDigest(rawToken)),
        DireccionIP: input(sql.VarChar(45), clientIp(request)),
        AgenteUsuario: input(sql.NVarChar(300), request.get('user-agent')?.slice(0, 300) ?? null),
        MinutosInactividad: input(sql.SmallInt, config.sessionIdleMinutes),
        HorasAbsolutas: input(sql.TinyInt, config.sessionAbsoluteHours),
        CorrelationId: input(sql.UniqueIdentifier, request.correlationId),
      });
      const user = normalizeSession(result);
      response.cookie(config.cookie.name, rawToken, cookieOptions(config));
      response.status(200).json({
        data: {
          user,
          csrfToken: csrfToken(rawToken, config.csrfSecret),
          locale: { currency: config.currencyCode, timeZone: config.timeZone },
        },
      });
    }),
  );

  router.get(
    '/session',
    authenticate({ touch: false, allowPasswordChangeOnly: true }),
    asyncHandler(async (request, response) => {
      const config = request.app.locals.config;
      response.json({
        data: {
          user: request.user,
          csrfToken: csrfToken(request.sessionToken, config.csrfSecret),
          locale: { currency: config.currencyCode, timeZone: config.timeZone },
        },
      });
    }),
  );

  router.post(
    '/logout',
    authenticate({ allowPasswordChangeOnly: true }),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const config = request.app.locals.config;
      try {
        await request.app.locals.database.execute('dbo.sp_CerrarSesion', {
          ...sessionParameters(request),
        });
      } finally {
        response.clearCookie(config.cookie.name, cookieOptions(config));
      }
      response.status(204).end();
    }),
  );

  router.post(
    '/recover',
    publicRateLimit,
    asyncHandler(async (request, response) => {
      const body = recoverSchema.parse(request.body);
      const config = request.app.locals.config;
      const rawToken = randomToken();
      const result = await request.app.locals.database.execute('dbo.sp_SolicitarRecuperacion', {
        Identidad: input(sql.NVarChar(254), body.identity),
        TokenHash: input(sql.VarBinary(64), tokenDigest(rawToken)),
        MinutosVigencia: input(sql.TinyInt, config.passwordResetMinutes),
        DireccionIP: input(sql.VarChar(45), clientIp(request)),
        CorrelationId: input(sql.UniqueIdentifier, request.correlationId),
      });
      try {
        await deliverRecoveryMessage(
          config,
          result.recordsets?.[0]?.[0] ?? null,
          rawToken,
          request.correlationId,
        );
      } catch (error) {
        console.error('No se pudo entregar una recuperación en el buzón local.', {
          correlationId: request.correlationId,
          code: error.code,
          name: error.name,
        });
      }
      response.status(202).json({
        data: {
          message:
            'Si la cuenta existe y está habilitada, se generó una instrucción de recuperación.',
        },
      });
    }),
  );

  router.post(
    '/reset',
    publicRateLimit,
    asyncHandler(async (request, response) => {
      const body = resetSchema.parse(request.body);
      await request.app.locals.database.execute('dbo.sp_RestablecerPassword', {
        TokenHash: input(sql.VarBinary(64), tokenDigest(body.token)),
        ContrasenaNueva: input(sql.NVarChar(128), body.newPassword),
        DireccionIP: input(sql.VarChar(45), clientIp(request)),
        CorrelationId: input(sql.UniqueIdentifier, request.correlationId),
      });
      response.json({ data: { message: 'La contraseña fue restablecida. Inicie sesión de nuevo.' } });
    }),
  );

  return router;
}
