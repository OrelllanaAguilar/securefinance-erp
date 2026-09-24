import { Router } from 'express';
import { z } from 'zod';
import { sql, input, inputTable } from '../db/database.js';
import { ApiError } from '../lib/api-error.js';
import { asyncHandler } from '../lib/async-handler.js';
import { pageParameters } from '../lib/parameters.js';
import { firstRow, listResult, saleResult } from '../lib/result.js';
import { moneySchema, parseBigIntId, uuidSchema } from '../lib/schemas.js';
import {
  authenticate,
  requireCsrf,
  requirePermission,
  sessionParameters,
} from '../middleware/session.js';

const saleLineSchema = z
  .object({
    productId: z.number().int().positive().max(2147483647),
    quantity: z.number().int().min(1).max(9999),
  })
  .strict();

const linesSchema = z
  .array(saleLineSchema)
  .min(1)
  .max(100)
  .refine(
    (lines) => new Set(lines.map((line) => line.productId)).size === lines.length,
    'Cada producto debe aparecer una sola vez; acumule su cantidad.',
  );

const quoteSchema = z
  .object({
    customerId: z.number().int().positive().max(2147483647),
    lines: linesSchema,
  })
  .strict();

const processSaleSchema = quoteSchema
  .extend({
    acceptedTotal: moneySchema,
    idempotencyKey: uuidSchema,
  })
  .strict();

const salesQuerySchema = z
  .object({
    page: z.coerce.number().int().positive().default(1),
    pageSize: z.enum(['10', '25', '50']).default('25').transform(Number),
    search: z.string().max(160).default(''),
    sort: z.enum(['date', 'number', 'customer', 'total']).default('date'),
    direction: z.enum(['asc', 'desc']).default('desc'),
    from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    scope: z.enum(['mine', 'all']).default('mine'),
  })
  .strict();

function detailTable(lines) {
  const table = new sql.Table('dbo.TVP_DetalleFactura');
  table.columns.add('ProductoId', sql.Int, { nullable: false });
  table.columns.add('Cantidad', sql.Int, { nullable: false });
  for (const line of lines) table.rows.add(line.productId, line.quantity);
  return table;
}

export function createSalesRouter() {
  const router = Router();

  router.post(
    '/quote',
    authenticate(),
    requirePermission('VENTAS_CREAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = quoteSchema.parse(request.body);
      const result = await request.app.locals.database.execute('dbo.sp_CotizarVenta', {
        ...sessionParameters(request),
        ClienteId: input(sql.Int, body.customerId),
        Detalle: inputTable(detailTable(body.lines)),
      });
      response.json({ data: saleResult(result) });
    }),
  );

  router.post(
    '/',
    authenticate(),
    requirePermission('VENTAS_CREAR'),
    requireCsrf,
    asyncHandler(async (request, response) => {
      const body = processSaleSchema.parse(request.body);
      try {
        const result = await request.app.locals.database.execute(
          'dbo.sp_ProcesarVentaTransaccional',
          {
            ...sessionParameters(request),
            ClienteId: input(sql.Int, body.customerId),
            Detalle: inputTable(detailTable(body.lines)),
            TotalAceptadoTexto: input(sql.VarChar(40), body.acceptedTotal),
            ClaveIdempotencia: input(sql.UniqueIdentifier, body.idempotencyKey),
          },
          { timeout: 30000 },
        );
        response.status(result.recordsets?.[0]?.[0]?.replayed ? 200 : 201).json({
          data: firstRow(result),
        });
      } catch (error) {
        if (error.status >= 500) {
          throw new ApiError(
            503,
            'SALE_RESULT_UNKNOWN',
            'No se confirmó el resultado. Conserve esta venta y consulte con la misma clave.',
            { cause: error, details: { idempotencyKey: body.idempotencyKey } },
          );
        }
        throw error;
      }
    }),
  );

  router.get(
    '/',
    authenticate(),
    requirePermission('VENTAS_CREAR', 'REPORTES_LEER'),
    asyncHandler(async (request, response) => {
      const query = salesQuerySchema.parse(request.query);
      const result = await request.app.locals.database.execute('dbo.sp_ConsultarVentasPropias', {
        ...sessionParameters(request),
        ...pageParameters(query),
        FechaDesde: input(sql.VarChar(10), query.from ?? null),
        FechaHasta: input(sql.VarChar(10), query.to ?? null),
        Alcance: input(sql.VarChar(4), query.scope),
      });
      response.json(listResult(result));
    }),
  );

  router.get(
    '/result/:key',
    authenticate(),
    requirePermission('VENTAS_CREAR'),
    asyncHandler(async (request, response) => {
      const key = uuidSchema.parse(request.params.key);
      const result = await request.app.locals.database.execute(
        'dbo.sp_ConsultarResultadoVenta',
        {
          ...sessionParameters(request),
          ClaveIdempotencia: input(sql.UniqueIdentifier, key),
        },
      );
      const data = firstRow(result);
      response.status(data ? 200 : 202).json({
        data: data ?? { status: 'pending', idempotencyKey: key },
      });
    }),
  );

  router.get(
    '/:id',
    authenticate(),
    requirePermission('VENTAS_CREAR', 'REPORTES_LEER'),
    asyncHandler(async (request, response) => {
      const id = parseBigIntId(request.params);
      const result = await request.app.locals.database.execute('dbo.sp_ConsultarFactura', {
        ...sessionParameters(request),
        FacturaId: input(sql.BigInt, id),
      });
      const invoice = result.recordsets?.[0]?.[0] ?? {};
      response.json({
        data: {
          ...invoice,
          lines: result.recordsets?.[1] ?? [],
          cashMovement: result.recordsets?.[2]?.[0] ?? null,
        },
      });
    }),
  );

  return router;
}
