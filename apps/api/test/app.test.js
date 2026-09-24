import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';

const csrfSecret = 'test-secret-that-is-longer-than-thirty-two-characters';

function testConfig() {
  return {
    nodeEnv: 'test',
    isProduction: false,
    host: '127.0.0.1',
    port: 3000,
    trustProxy: false,
    appOrigin: 'http://127.0.0.1:3000',
    allowedOrigins: ['http://127.0.0.1:3000'],
    cookie: {
      name: 'sf_session',
      secure: false,
      httpOnly: true,
      sameSite: 'strict',
      path: '/',
      maxAge: 28800000,
    },
    csrfSecret,
    sessionIdleMinutes: 30,
    sessionAbsoluteHours: 8,
    passwordResetMinutes: 15,
    currencyCode: 'GTQ',
    timeZone: 'America/Guatemala',
    mailboxPath: 'C:/nonexistent/private-mailbox',
    webDistPath: 'C:/nonexistent/web-dist',
  };
}

function sessionRecordsets(permissions = [], overrides = {}) {
  return [
    [
      {
        userId: 7,
        username: 'cajero.demo',
        displayName: 'Cajero Demo',
        email: null,
        mustChangePassword: false,
        theme: 'sistema',
        version: '0x0000000000000001',
        sessionExpiresAt: '2026-09-22T21:30:00.000Z',
        absoluteExpiresAt: '2026-09-23T05:00:00.000Z',
        ...overrides,
      },
    ],
    permissions.map((code) => ({ code })),
    [{ name: 'Cajero' }],
  ];
}

function fakeDatabase(permissions = ['VENTAS_CREAR'], sessionOverrides = {}) {
  return {
    execute: vi.fn(async (procedure) => {
      if (procedure === 'dbo.sp_AutenticarUsuario' || procedure === 'dbo.sp_ValidarSesionApi') {
        return { recordsets: sessionRecordsets(permissions, sessionOverrides) };
      }
      if (procedure === 'dbo.sp_VerificarEstado') {
        return { recordsets: [[{ databaseStatus: 'available' }]] };
      }
      return { recordsets: [[]] };
    }),
  };
}

describe('API HTTP', () => {
  it('inicia sesión con cookie HttpOnly y entrega CSRF en memoria', async () => {
    const database = fakeDatabase();
    const app = createApp({ config: testConfig(), database });

    const response = await request(app).post('/api/auth/login').send({
      username: 'cajero.demo',
      password: 'Clave-Temporal-9!',
    });

    expect(response.status).toBe(200);
    expect(response.body.data.csrfToken).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(response.headers['set-cookie'][0]).toContain('HttpOnly');
    expect(response.headers['set-cookie'][0]).toContain('SameSite=Strict');
    expect(database.execute).toHaveBeenCalledWith(
      'dbo.sp_AutenticarUsuario',
      expect.objectContaining({ NombreUsuario: expect.any(Object) }),
    );
  });

  it('rechaza campos inesperados sin invocar SQL', async () => {
    const database = fakeDatabase();
    const app = createApp({ config: testConfig(), database });

    const response = await request(app).post('/api/auth/login').send({
      username: 'cajero.demo',
      password: 'Clave-Temporal-9!',
      isAdmin: true,
    });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
    expect(database.execute).not.toHaveBeenCalled();
  });

  it('rechaza mutaciones procedentes de otro origen', async () => {
    const database = fakeDatabase();
    const app = createApp({ config: testConfig(), database });

    const response = await request(app)
      .post('/api/auth/login')
      .set('Origin', 'https://sitio-ajeno.example')
      .send({ username: 'cajero.demo', password: 'Clave-Temporal-9!' });

    expect(response.status).toBe(403);
    expect(response.body.error.code).toBe('ORIGIN_INVALID');
    expect(database.execute).not.toHaveBeenCalled();
  });

  it('no permite una mutación sin verificación CSRF', async () => {
    const database = fakeDatabase(['PRODUCTOS_GESTIONAR']);
    const app = createApp({ config: testConfig(), database });
    const login = await request(app).post('/api/auth/login').send({
      username: 'admin.demo',
      password: 'Clave-Temporal-9!',
    });
    const cookie = login.headers['set-cookie'][0].split(';')[0];

    const response = await request(app)
      .post('/api/products')
      .set('Cookie', cookie)
      .send({ code: 'P-1', description: 'Producto', unit: 'unidad', price: '10.00' });

    expect(response.status).toBe(403);
    expect(response.body.error.code).toBe('CSRF_INVALID');
  });

  it('aplica permisos en API aun cuando se llama directamente', async () => {
    const database = fakeDatabase([]);
    const app = createApp({ config: testConfig(), database });
    const login = await request(app).post('/api/auth/login').send({
      username: 'cajero.demo',
      password: 'Clave-Temporal-9!',
    });
    const cookie = login.headers['set-cookie'][0].split(';')[0];

    const response = await request(app).get('/api/audit/access').set('Cookie', cookie);

    expect(response.status).toBe(403);
    expect(response.body.error.code).toBe('FORBIDDEN');
  });

  it('no renueva inactividad durante la consulta automática de sesión', async () => {
    const database = fakeDatabase();
    const app = createApp({ config: testConfig(), database });
    const login = await request(app).post('/api/auth/login').send({
      username: 'cajero.demo',
      password: 'Clave-Temporal-9!',
    });
    const cookie = login.headers['set-cookie'][0].split(';')[0];

    const response = await request(app).get('/api/auth/session').set('Cookie', cookie);

    expect(response.status).toBe(200);
    expect(database.execute).toHaveBeenLastCalledWith(
      'dbo.sp_ValidarSesionApi',
      expect.objectContaining({ ActualizarActividad: expect.objectContaining({ value: false }) }),
    );
  });

  it('limita una sesión de cambio obligatorio a seguridad y cierre', async () => {
    const database = fakeDatabase(['REPORTES_LEER'], { mustChangePassword: true });
    const app = createApp({ config: testConfig(), database });
    const login = await request(app).post('/api/auth/login').send({
      username: 'admin.demo',
      password: 'Clave-Temporal-9!',
    });
    const cookie = login.headers['set-cookie'][0].split(';')[0];
    const csrf = login.body.data.csrfToken;

    const denied = await request(app).get('/api/dashboard').set('Cookie', cookie);
    expect(denied.status).toBe(403);
    expect(denied.body.error.code).toBe('PASSWORD_CHANGE_REQUIRED');

    const changed = await request(app)
      .put('/api/me/password')
      .set('Cookie', cookie)
      .set('x-csrf-token', csrf)
      .send({ currentPassword: 'Clave-Temporal-9!', newPassword: 'Nueva-Clave-Segura-8!' });
    expect(changed.status).toBe(200);
    expect(database.execute).toHaveBeenLastCalledWith(
      'dbo.sp_CambiarPassword',
      expect.objectContaining({ ContrasenaNueva: expect.any(Object) }),
    );
  });

  it('responde 404 en rutas API inexistentes sin servir el SPA', async () => {
    const app = createApp({ config: testConfig(), database: fakeDatabase() });
    const response = await request(app).get('/api/no-existe');
    expect(response.status).toBe(404);
    expect(response.body.error.code).toBe('ROUTE_NOT_FOUND');
  });
});
