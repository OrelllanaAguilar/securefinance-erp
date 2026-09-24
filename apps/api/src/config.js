import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { z } from 'zod';

const apiDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(apiDirectory, '../../..');
dotenv.config({ path: path.join(repositoryRoot, '.env'), quiet: true });

const booleanValue = (defaultValue) => z
  .enum(['true', 'false'])
  .default(defaultValue)
  .transform((value) => value === 'true');

const optionalPort = z
  .string()
  .optional()
  .transform((value) => (value ? Number(value) : undefined))
  .pipe(z.number().int().min(1).max(65535).optional());

const privateValue = (minimum, label) => z
  .string()
  .min(minimum)
  .refine((value) => !/^replace-with-/iu.test(value), `${label} no puede conservar el marcador de .env.example.`);

const environmentSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    HOST: z.literal('127.0.0.1').default('127.0.0.1'),
    PORT: z.coerce.number().int().min(1).max(65535).default(3000),
    TRUST_PROXY: booleanValue('false'),
    APP_ORIGIN: z.string().url().default('http://127.0.0.1:3000'),
    DEV_ORIGIN: z.string().url().default('http://127.0.0.1:5173'),
    COOKIE_SECURE: booleanValue('false'),
    COOKIE_NAME: z.string().regex(/^[A-Za-z0-9_-]+$/).default('sf_session'),
    CSRF_SECRET: privateValue(32, 'CSRF_SECRET'),
    SESSION_IDLE_MINUTES: z.coerce.number().int().min(5).max(120).default(30),
    SESSION_ABSOLUTE_HOURS: z.coerce.number().int().min(1).max(24).default(8),
    PASSWORD_RESET_MINUTES: z.coerce.number().int().min(5).max(60).default(15),
    CURRENCY_CODE: z.string().regex(/^[A-Z]{3}$/).default('GTQ'),
    TIME_ZONE: z.string().min(1).default('America/Guatemala'),
    RECOVERY_MAILBOX_DIR: z.string().default('./private-mailbox'),
    WEB_DIST_DIR: z.string().default('../web/dist'),
    DB_SERVER: z.string().min(1),
    DB_INSTANCE: z.string().optional().default(''),
    DB_PORT: optionalPort,
    DB_NAME: z.string().regex(/^[A-Za-z0-9_]+$/),
    DB_USER: z.string().min(1),
    DB_PASSWORD: privateValue(16, 'DB_PASSWORD'),
    DB_ENCRYPT: booleanValue('false'),
    DB_TRUST_SERVER_CERTIFICATE: booleanValue('true'),
    DB_POOL_MAX: z.coerce.number().int().min(1).max(100).default(10),
    DB_REQUEST_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120000).default(15000),
  })
  .superRefine((values, context) => {
    for (const field of ['APP_ORIGIN', 'DEV_ORIGIN']) {
      const url = new URL(values[field]);
      if (
        !['http:', 'https:'].includes(url.protocol)
        ||
        !['127.0.0.1', 'localhost'].includes(url.hostname)
        || url.username
        || url.password
        || (url.pathname !== '/' && url.pathname !== '')
        || url.search
        || url.hash
      ) {
        context.addIssue({
          code: 'custom',
          path: [field],
          message: 'Debe ser un origen de loopback sin ruta, credenciales, consulta ni fragmento.',
        });
      }
    }
    if (values.DB_INSTANCE && values.DB_PORT) {
      context.addIssue({
        code: 'custom',
        path: ['DB_PORT'],
        message: 'DB_INSTANCE y DB_PORT no pueden configurarse a la vez.',
      });
    }
    if (values.COOKIE_SECURE && !values.APP_ORIGIN.startsWith('https://')) {
      context.addIssue({
        code: 'custom',
        path: ['APP_ORIGIN'],
        message: 'COOKIE_SECURE requiere un APP_ORIGIN HTTPS.',
      });
    }
    try {
      new Intl.DateTimeFormat('en', { timeZone: values.TIME_ZONE }).format(new Date());
    } catch {
      context.addIssue({
        code: 'custom',
        path: ['TIME_ZONE'],
        message: 'Debe ser una zona horaria IANA reconocida por este runtime.',
      });
    }
  });

export function loadConfig(environment = process.env) {
  const parsed = environmentSchema.safeParse(environment);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((issue) => `${issue.path.join('.')}: ${issue.message}`)
      .join('; ');
    throw new Error(`Configuración inválida: ${details}`);
  }

  const env = parsed.data;
  const appOrigin = new URL(env.APP_ORIGIN).origin;
  const devOrigin = new URL(env.DEV_ORIGIN).origin;
  const mailboxPath = path.resolve(repositoryRoot, env.RECOVERY_MAILBOX_DIR);
  const webDistPath = path.resolve(apiDirectory, '..', env.WEB_DIST_DIR);
  const databaseOptions = {
    server: env.DB_SERVER,
    database: env.DB_NAME,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    connectionTimeout: env.DB_REQUEST_TIMEOUT_MS,
    requestTimeout: env.DB_REQUEST_TIMEOUT_MS,
    pool: {
      min: 0,
      max: env.DB_POOL_MAX,
      idleTimeoutMillis: 30000,
    },
    options: {
      encrypt: env.DB_ENCRYPT,
      trustServerCertificate: env.DB_TRUST_SERVER_CERTIFICATE,
      enableArithAbort: true,
      appName: 'SecureFinanceERP-API',
      ...(env.DB_INSTANCE ? { instanceName: env.DB_INSTANCE } : {}),
    },
    ...(env.DB_PORT ? { port: env.DB_PORT } : {}),
  };

  return Object.freeze({
    nodeEnv: env.NODE_ENV,
    isProduction: env.NODE_ENV === 'production',
    host: env.HOST,
    port: env.PORT,
    trustProxy: env.TRUST_PROXY,
    appOrigin,
    allowedOrigins: Object.freeze(
      env.NODE_ENV === 'development'
        ? [...new Set([appOrigin, devOrigin])]
        : [appOrigin],
    ),
    cookie: Object.freeze({
      name: env.COOKIE_NAME,
      secure: env.COOKIE_SECURE,
      httpOnly: true,
      sameSite: 'strict',
      path: '/',
      maxAge: env.SESSION_ABSOLUTE_HOURS * 60 * 60 * 1000,
    }),
    csrfSecret: env.CSRF_SECRET,
    sessionIdleMinutes: env.SESSION_IDLE_MINUTES,
    sessionAbsoluteHours: env.SESSION_ABSOLUTE_HOURS,
    passwordResetMinutes: env.PASSWORD_RESET_MINUTES,
    currencyCode: env.CURRENCY_CODE,
    timeZone: env.TIME_ZONE,
    mailboxPath,
    webDistPath,
    database: Object.freeze(databaseOptions),
  });
}
