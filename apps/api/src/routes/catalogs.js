import { Router } from 'express';
import { z } from 'zod';
import { sql, input } from '../db/database.js';
import { asyncHandler } from '../lib/async-handler.js';
import { pageParameters, rowVersionBuffer } from '../lib/parameters.js';
import { firstRow, listResult } from '../lib/result.js';
import { moneySchema, parseId } from '../lib/schemas.js';
import {
  authenticate,
  requireCsrf,
  requirePermission,
  sessionParameters,
} from '../middleware/session.js';

const pageSize = z.enum(['10', '25', '50']).default('25').transform(Number);
const rowVersion = z.string().regex(/^0x[0-9A-Fa-f]{16}$/);
const productPrice = moneySchema.refine((value) => {
  const [integer, fraction] = value.split('.');
  const cents = BigInt(integer) * 100n + BigInt(fraction);
  return cents >= 1n && cents <= 99999999n;
}, 'El precio debe estar entre 0.01 y 999999.99.');

const productQuerySchema = z
  .object({
    page: z.coerce.number().int().positive().default(1),
    pageSize,
    search: z.string().max(160).default(''),
    status: z.enum(['all', 'active', 'inactive']).default('all'),
    sort: z.enum(['code', 'description', 'price', 'stock', 'updatedAt']).default('code'),
    direction: z.enum(['asc', 'desc']).default('asc'),
  })
  .strict();

const productCreateSchema = z
  .object({
    code: z.string().trim().min(1).max(30),
    description: z.string().trim().min(2).max(160),
    unit: z.string().trim().min(1).max(20),
    price: productPrice,
  })
  .strict();

const productUpdateSchema = productCreateSchema
  .partial()
  .extend({
    active: z.boolean().optional(),
    version: rowVersion,
  })
  .strict()
  .refine(
    (value) => Object.keys(value).some((key) => key !== 'version'),
    'Incluya al menos un campo para actualizar.',
  );

const inventorySchema = z
  .object({
    delta: z.number().int().min(-999999).max(999999).refine((value) => value !== 0),
    reason: z.string().trim().min(10).max(250),
    version: rowVersion,
  })
  .strict();

const customerQuerySchema = z
  .object({
    page: z.coerce.number().int().positive().default(1),
    pageSize,
    search: z.string().max(160).default(''),
    status: z.enum(['all', 'active', 'inactive']).default('all'),
    sort: z.enum(['identifier', 'name', 'email', 'updatedAt']).default('name'),
    direction: z.enum(['asc', 'desc']).default('asc'),
  })
  .strict();

const nullableText = (maximum) => z.union([z.string().trim().max(maximum), z.literal(''), z.null()]);
const customerCreateSchema = z
  .object({
    identifier: z.string().trim().min(1).max(30),
    name: z.string().trim().min(2).max(120),
    email: nullableText(254).optional(),
    phone: nullableText(30).optional(),
  })
  .strict();

const customerUpdateSchema = customerCreateSchema
  .partial()
  .extend({ active: z.boolean().optional(), version: rowVersion })
  .strict()
  .refine(
    (value) => Object.keys(value).some((key) => key !== 'version'),
    'Incluya al menos un campo para actualizar.',
  );

export function createProductsRouter() {
  const router = Router();

  router.get(
    '/',
    authenticate(),
    requirePermission('VENTAS_CREAR', 'PRODUCTOS_GESTIONAR'),
    asyncHandler(async (request, response) => {
      const query = productQuerySchema.parse(request.query);
      const result = await request.app.locals.database.execute('dbo.sp_ListarProductos', {
        ...sessionParameters(request),
        ...pageParameters(query),
        Estado: input(sql.VarChar(8), query.status),
      });
      response.json(listResult(result));
    }),
  );

  router.get(
    '/options',
    authenticate(),
    requirePermission('VENTAS_CREAR', 'PRODUCTOS_GESTIONAR'),
    asyncHandler(async (request, response) => {
      const result = await request.app.locals.database.execute('dbo.sp_ListarUnidadesMedida', {
        ...sessionParameters(request),
      });
      response.json({ data: result.recordsets?.[0] ?? [] });
    }),
  );

  router.post(
    '/',
    authenticate(),
    requirePermission('PRODUCTOS_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = productCreateSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_CrearProducto', {
        ...sessionParameters(request),
        Codigo: input(sql.VarChar(30), body.code),
        Descripcion: input(sql.NVarChar(160), body.description),
        Unidad: input(sql.VarChar(20), body.unit),
        PrecioTexto: input(sql.VarChar(40), body.price),
      });
      response.status(201).json({ data: firstRow(result) });
    }),
  );

  router.patch(
    '/:id',
    authenticate(),
    requirePermission('PRODUCTOS_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const id = parseId(request.params);
      const body = productUpdateSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_ActualizarProducto', {
        ...sessionParameters(request),
        ProductoId: input(sql.Int, id),
        Codigo: input(sql.VarChar(30), body.code ?? null),
        Descripcion: input(sql.NVarChar(160), body.description ?? null),
        Unidad: input(sql.VarChar(20), body.unit ?? null),
        PrecioTexto: input(sql.VarChar(40), body.price ?? null),
        Activo: input(sql.Bit, body.active ?? null),
        Version: input(sql.Binary(8), rowVersionBuffer(body.version)),
      });
      response.json({ data: firstRow(result) });
    }),
  );

  router.post(
    '/:id/inventory',
    authenticate(),
    requirePermission('PRODUCTOS_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const id = parseId(request.params);
      const body = inventorySchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_AjustarInventario', {
        ...sessionParameters(request),
        ProductoId: input(sql.Int, id),
        Variacion: input(sql.Int, body.delta),
        Motivo: input(sql.NVarChar(250), body.reason),
        Version: input(sql.Binary(8), rowVersionBuffer(body.version)),
      });
      response.json({ data: firstRow(result) });
    }),
  );

  return router;
}

export function createCustomersRouter() {
  const router = Router();

  router.get(
    '/',
    authenticate(),
    requirePermission('VENTAS_CREAR', 'CLIENTES_GESTIONAR'),
    asyncHandler(async (request, response) => {
      const query = customerQuerySchema.parse(request.query);
      const result = await request.app.locals.database.execute('dbo.sp_ListarClientes', {
        ...sessionParameters(request),
        ...pageParameters(query),
        Estado: input(sql.VarChar(8), query.status),
      });
      response.json(listResult(result));
    }),
  );

  router.post(
    '/',
    authenticate(),
    requirePermission('CLIENTES_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = customerCreateSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_CrearCliente', {
        ...sessionParameters(request),
        Identificador: input(sql.VarChar(30), body.identifier),
        Nombre: input(sql.NVarChar(120), body.name),
        Correo: input(sql.NVarChar(254), body.email || null),
        Telefono: input(sql.NVarChar(30), body.phone || null),
      });
      response.status(201).json({ data: firstRow(result) });
    }),
  );

  router.patch(
    '/:id',
    authenticate(),
    requirePermission('CLIENTES_GESTIONAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const id = parseId(request.params);
      const body = customerUpdateSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_ActualizarCliente', {
        ...sessionParameters(request),
        ClienteId: input(sql.Int, id),
        Identificador: input(sql.VarChar(30), body.identifier ?? null),
        Nombre: input(sql.NVarChar(120), body.name ?? null),
        Correo: input(sql.NVarChar(254), body.email === '' ? null : body.email),
        Telefono: input(sql.NVarChar(30), body.phone === '' ? null : body.phone),
        CambiarCorreo: input(sql.Bit, body.email !== undefined),
        CambiarTelefono: input(sql.Bit, body.phone !== undefined),
        Activo: input(sql.Bit, body.active ?? null),
        Version: input(sql.Binary(8), rowVersionBuffer(body.version)),
      });
      response.json({ data: firstRow(result) });
    }),
  );

  return router;
}
