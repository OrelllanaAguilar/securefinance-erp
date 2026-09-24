import { Router } from 'express';
import { z } from 'zod';
import { sql, input, inputTable } from '../db/database.js';
import { asyncHandler } from '../lib/async-handler.js';
import { pageParameters, rowVersionBuffer } from '../lib/parameters.js';
import { firstRow, listResult } from '../lib/result.js';
import { parseId, usernameSchema } from '../lib/schemas.js';
import { temporaryPassword } from '../lib/security.js';
import {
  authenticate,
  requireCsrf,
  requirePermission,
  sessionParameters,
} from '../middleware/session.js';

const permissions = [
  'AUDITORIA_LEER',
  'CLIENTES_GESTIONAR',
  'PRODUCTOS_GESTIONAR',
  'REPORTES_LEER',
  'ROLES_GESTIONAR',
  'USUARIOS_GESTIONAR',
  'VENTAS_CREAR',
];

const permissionSchema = z.enum(permissions);
const rowVersion = z.string().regex(/^0x[0-9A-Fa-f]{16}$/);
const pageSize = z.enum(['10', '25', '50']).default('25').transform(Number);

const listQuerySchema = z
  .object({
    page: z.coerce.number().int().positive().default(1),
    pageSize,
    search: z.string().max(160).default(''),
    sort: z.enum(['name', 'username', 'status', 'updatedAt']).default('name'),
    direction: z.enum(['asc', 'desc']).default('asc'),
  })
  .strict();

const roleCreateSchema = z
  .object({
    name: z.string().trim().min(3).max(60),
    description: z.union([z.string().trim().max(200), z.literal(''), z.null()]).optional(),
    permissions: z.array(permissionSchema).max(permissions.length).default([]),
  })
  .strict();

const roleUpdateSchema = roleCreateSchema
  .partial()
  .extend({ active: z.boolean().optional(), version: rowVersion })
  .strict()
  .refine(
    (value) => Object.keys(value).some((key) => key !== 'version'),
    'Incluya al menos un campo para actualizar.',
  );

const emailSchema = z.union([z.string().email().max(254), z.literal(''), z.null()]);
const roleIdsSchema = z.array(z.number().int().positive().max(2147483647)).max(30);
const userCreateSchema = z
  .object({
    username: usernameSchema,
    displayName: z.string().trim().min(2).max(120),
    email: emailSchema.optional(),
    roleIds: roleIdsSchema.default([]),
  })
  .strict();

const userUpdateSchema = z
  .object({
    displayName: z.string().trim().min(2).max(120).optional(),
    email: emailSchema.optional(),
    active: z.boolean().optional(),
    roleIds: roleIdsSchema.optional(),
    version: rowVersion,
  })
  .strict()
  .refine(
    (value) => Object.keys(value).some((key) => key !== 'version'),
    'Incluya al menos un campo para actualizar.',
  );

function idsTable(ids) {
  const table = new sql.Table('dbo.TVP_ListaEnteros');
  table.columns.add('Id', sql.Int, { nullable: false });
  for (const id of ids ?? []) table.rows.add(id);
  return table;
}

function codesTable(codes) {
  const table = new sql.Table('dbo.TVP_CodigosPermiso');
  table.columns.add('Codigo', sql.VarChar(50), { nullable: false });
  for (const code of codes ?? []) table.rows.add(code);
  return table;
}

export function createUsersRouter() {
  const router = Router();

  router.get(
    '/',
    authenticate(),
    requirePermission('USUARIOS_GESTIONAR'),
    asyncHandler(async (request, response) => {
      const query = listQuerySchema.parse(request.query);
      const result = await request.app.locals.database.execute('dbo.sp_ListarUsuarios', {
        ...sessionParameters(request),
        ...pageParameters(query),
      });
      response.json(listResult(result));
    }),
  );

  router.post(
    '/',
    authenticate(),
    requirePermission('USUARIOS_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = userCreateSchema.parse(request.body);
      const password = temporaryPassword();
      const result = await request.app.locals.database.execute('dbo.sp_CrearUsuario', {
        ...sessionParameters(request),
        NombreUsuario: input(sql.VarChar(50), body.username),
        NombreVisible: input(sql.NVarChar(120), body.displayName),
        Correo: input(sql.NVarChar(254), body.email || null),
        PasswordTemporal: input(sql.NVarChar(128), password),
        Roles: inputTable(idsTable(body.roleIds)),
      });
      response.status(201).json({
        data: {
          user: firstRow(result),
          temporaryPassword: password,
          message: 'Entregue esta credencial por un canal privado; solo se muestra una vez.',
        },
      });
    }),
  );

  router.patch(
    '/:id',
    authenticate(),
    requirePermission('USUARIOS_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const id = parseId(request.params);
      const body = userUpdateSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_ActualizarUsuario', {
        ...sessionParameters(request),
        UsuarioId: input(sql.Int, id),
        NombreVisible: input(sql.NVarChar(120), body.displayName ?? null),
        Correo: input(sql.NVarChar(254), body.email === '' ? null : body.email),
        CambiarCorreo: input(sql.Bit, body.email !== undefined),
        Activo: input(sql.Bit, body.active ?? null),
        CambiarRoles: input(sql.Bit, body.roleIds !== undefined),
        Roles: inputTable(idsTable(body.roleIds)),
        Version: input(sql.Binary(8), rowVersionBuffer(body.version)),
      });
      response.json({ data: firstRow(result) });
    }),
  );

  router.post(
    '/:id/reset-password',
    authenticate(),
    requirePermission('USUARIOS_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const id = parseId(request.params);
      z.object({}).strict().parse(request.body ?? {});
      const password = temporaryPassword();
      await request.app.locals.database.execute('dbo.sp_GenerarPasswordTemporal', {
        ...sessionParameters(request),
        UsuarioId: input(sql.Int, id),
        PasswordTemporal: input(sql.NVarChar(128), password),
      });
      response.json({
        data: {
          temporaryPassword: password,
          message: 'Entregue esta credencial por un canal privado; solo se muestra una vez.',
        },
      });
    }),
  );

  return router;
}

export function createRolesRouter() {
  const router = Router();

  router.get(
    '/',
    authenticate(),
    requirePermission('ROLES_GESTIONAR'),
    asyncHandler(async (request, response) => {
      const query = listQuerySchema.parse(request.query);
      const result = await request.app.locals.database.execute('dbo.sp_ListarRoles', {
        ...sessionParameters(request),
        ...pageParameters(query),
      });
      response.json(listResult(result));
    }),
  );

  router.post(
    '/',
    authenticate(),
    requirePermission('ROLES_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = roleCreateSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_CrearRol', {
        ...sessionParameters(request),
        Nombre: input(sql.NVarChar(60), body.name),
        Descripcion: input(sql.NVarChar(200), body.description || null),
        Permisos: inputTable(codesTable(body.permissions)),
      });
      response.status(201).json({ data: firstRow(result) });
    }),
  );

  router.patch(
    '/:id',
    authenticate(),
    requirePermission('ROLES_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const id = parseId(request.params);
      const body = roleUpdateSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_ActualizarRol', {
        ...sessionParameters(request),
        RolId: input(sql.Int, id),
        Nombre: input(sql.NVarChar(60), body.name ?? null),
        Descripcion: input(sql.NVarChar(200), body.description === '' ? null : body.description),
        CambiarDescripcion: input(sql.Bit, body.description !== undefined),
        Activo: input(sql.Bit, body.active ?? null),
        CambiarPermisos: input(sql.Bit, body.permissions !== undefined),
        Permisos: inputTable(codesTable(body.permissions)),
        Version: input(sql.Binary(8), rowVersionBuffer(body.version)),
      });
      response.json({ data: firstRow(result) });
    }),
  );

  return router;
}

export function createPermissionsRouter() {
  const router = Router();
  router.get(
    '/',
    authenticate(),
    requirePermission('ROLES_GESTIONAR'),
    asyncHandler(async (request, response) => {
      const result = await request.app.locals.database.execute('dbo.sp_ListarPermisos', {
        ...sessionParameters(request),
      });
      response.json({ data: result.recordsets?.[0] ?? [] });
    }),
  );
  return router;
}
