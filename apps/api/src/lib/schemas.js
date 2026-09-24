import { z } from 'zod';

export const passwordSchema = z
  .string()
  .min(12, 'Debe contener al menos 12 caracteres.')
  .max(128, 'No puede superar 128 caracteres.')
  .refine((value) => /[A-Z]/.test(value), 'Debe incluir una mayúscula.')
  .refine((value) => /[a-z]/.test(value), 'Debe incluir una minúscula.')
  .refine((value) => /[0-9]/.test(value), 'Debe incluir un número.')
  .refine((value) => /[^A-Za-z0-9]/.test(value), 'Debe incluir un símbolo.');

export const usernameSchema = z
  .string()
  .min(3)
  .max(50)
  .regex(/^[A-Za-z0-9._-]+$/, 'Use letras ASCII, números, punto, guion o guion bajo.');

export const moneySchema = z
  .string()
  .regex(/^(?:0|[1-9]\d{0,16})\.\d{2}$/, 'Use un importe decimal con exactamente dos decimales.');

export const positiveIdSchema = z.coerce.number().int().positive().max(2147483647);

const positiveBigIntIdSchema = z
  .string()
  .regex(/^[1-9]\d*$/, 'Use un identificador entero positivo.')
  .refine((value) => BigInt(value) <= 9223372036854775807n, 'El identificador excede BIGINT.')
  .transform((value) => BigInt(value));

export const pageQuerySchema = z
  .object({
    page: z.coerce.number().int().positive().default(1),
    pageSize: z
      .enum(['10', '25', '50'])
      .default('25')
      .transform(Number),
    search: z.string().max(160).default(''),
    sort: z.string().max(40).optional(),
    direction: z.enum(['asc', 'desc']).default('asc'),
  })
  .strict();

export const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use la fecha aaaa-mm-dd.');

export const themeSchema = z.enum(['claro', 'oscuro', 'sistema']);

export const uuidSchema = z.string().uuid();

export function parseId(parameters) {
  return positiveIdSchema.parse(parameters.id);
}

export function parseBigIntId(parameters) {
  return positiveBigIntIdSchema.parse(parameters.id);
}
