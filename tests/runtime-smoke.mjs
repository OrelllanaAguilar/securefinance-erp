import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const environmentPath = path.join(root, '.env');
const firstAccessPath = path.join(root, 'secrets', 'first-access.txt');
const currentAccessPath = path.join(root, 'secrets', 'test-current-access.json');
const evidenceDirectory = path.join(root, 'docs', 'evidence', 'runtime');
const checkpoints = [];

function parseEnvironment(text) {
  return Object.fromEntries(
    text
      .split(/\r?\n/u)
      .filter((line) => line && !line.trimStart().startsWith('#') && line.includes('='))
      .map((line) => {
        const separator = line.indexOf('=');
        return [line.slice(0, separator), line.slice(separator + 1)];
      }),
  );
}

function generatedPassword() {
  return `Aa7!${crypto.randomBytes(21).toString('base64url')}`;
}

function localDate(timeZone) {
  const parts = new Intl.DateTimeFormat('en', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

async function readPrivateAccess() {
  try {
    return { credentials: JSON.parse(await fs.readFile(currentAccessPath, 'utf8')), initial: false };
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const text = await fs.readFile(firstAccessPath, 'utf8');
  const username = /^Usuario:\s*(.+)$/mu.exec(text)?.[1];
  // Windows PowerShell 5.1 can reinterpret a UTF-8 script without BOM as an
  // ANSI file. Accept both the new ASCII label and previously generated files.
  const password = /^(?:Clave|Contrase.{1,2}a) temporal:\s*(.+)$/mu.exec(text)?.[1];
  if (!username || !password) throw new Error('El archivo de primer acceso no tiene el formato esperado.');
  return { credentials: { admin: { username, password } }, initial: true };
}

async function savePrivateAccess(credentials) {
  await fs.writeFile(currentAccessPath, `${JSON.stringify(credentials, null, 2)}\n`, {
    encoding: 'utf8',
    flag: 'w',
    mode: 0o600,
  });
}

const environment = parseEnvironment(await fs.readFile(environmentPath, 'utf8'));
if (!/_Test$/iu.test(environment.DB_NAME ?? '')) {
  throw new Error('La prueba smoke se niega a modificar una base cuyo nombre no termine en _Test.');
}
const baseUrl = environment.APP_ORIGIN;
if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/u.test(baseUrl ?? '')) {
  throw new Error('APP_ORIGIN debe ser un origen HTTP de loopback para esta prueba local.');
}

let cookie;
let csrf;

async function api(pathname, { method = 'GET', body, expected = [200] } = {}) {
  const headers = { accept: 'application/json' };
  if (cookie) headers.cookie = cookie;
  if (!['GET', 'HEAD'].includes(method)) {
    headers.origin = baseUrl;
    headers['content-type'] = 'application/json';
    if (csrf) headers['x-csrf-token'] = csrf;
  }
  const response = await fetch(new URL(pathname, baseUrl), {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const payload = response.status === 204 ? null : await response.json();
  checkpoints.push({ method, pathname, status: response.status, code: payload?.error?.code ?? null });
  if (!expected.includes(response.status)) {
    throw new Error(
      `${method} ${pathname} devolvió ${response.status} (${payload?.error?.code ?? 'sin-código'}): ${payload?.error?.message ?? 'respuesta inesperada'}`,
    );
  }
  return { response, payload };
}

async function login(username, password, expected = [200]) {
  cookie = undefined;
  csrf = undefined;
  const result = await api('/api/auth/login', {
    method: 'POST',
    body: { username, password },
    expected,
  });
  if (result.response.status === 200) {
    const setCookie = result.response.headers.getSetCookie?.()[0] ?? result.response.headers.get('set-cookie');
    cookie = setCookie?.split(';', 1)[0];
    csrf = result.payload.data.csrfToken;
    if (!cookie || !csrf) throw new Error('El acceso no entregó cookie opaca y token CSRF.');
  }
  return result.payload;
}

async function changePassword(currentPassword, newPassword) {
  await api('/api/me/password', {
    method: 'PUT',
    body: { currentPassword, newPassword },
  });
  cookie = undefined;
  csrf = undefined;
}

const startedAt = new Date();
let evidence;
try {
  const privateAccess = await readPrivateAccess();
  const credentials = privateAccess.credentials;
  let adminPassword = credentials.admin.password;
  let adminSession = await login(credentials.admin.username, adminPassword);

  if (adminSession.data.user.mustChangePassword) {
    await api('/api/dashboard', { expected: [403] });
    const replacement = generatedPassword();
    await changePassword(adminPassword, replacement);
    await login(credentials.admin.username, adminPassword, [400, 429]);
    adminPassword = replacement;
    credentials.admin.password = replacement;
    await savePrivateAccess(credentials);
    adminSession = await login(credentials.admin.username, adminPassword);
  }

  if (adminSession.data.user.permissions.includes('VENTAS_CREAR')) {
    throw new Error('El rol Administrador recibió VENTAS_CREAR por defecto.');
  }

  const strandedBootstrap = await api('/api/users?page=1&pageSize=25&search=admin.local&sort=username&direction=asc');
  const obsoleteAdmin = strandedBootstrap.payload.data.find(
    (account) => account.username === 'admin.local' && account.username !== credentials.admin.username && account.active !== false,
  );
  if (obsoleteAdmin) {
    await api(`/api/users/${obsoleteAdmin.id}`, {
      method: 'PATCH',
      body: { active: false, version: obsoleteAdmin.version },
    });
  }

  const roles = await api('/api/roles?page=1&pageSize=50&search=&sort=name&direction=asc');
  const cashierRole = roles.payload.data.find((role) => role.name === 'Cajero');
  if (!cashierRole) throw new Error('La semilla no contiene el rol Cajero.');

  const suffix = Date.now().toString(36);
  const product = await api('/api/products', {
    method: 'POST',
    expected: [201],
    body: {
      code: `SMK-${suffix}`.toUpperCase(),
      description: `Producto smoke ${suffix}`,
      unit: 'UNIDAD',
      price: '100.00',
    },
  });
  const stockedProduct = await api(`/api/products/${product.payload.data.id}/inventory`, {
    method: 'POST',
    body: { delta: 3, reason: 'Existencia aislada para prueba smoke', version: product.payload.data.version },
  });
  if (stockedProduct.payload.data.stock !== 3) throw new Error('El ajuste de inventario no dejó stock 3.');

  const customer = await api('/api/customers', {
    method: 'POST',
    expected: [201],
    body: {
      identifier: `SMK-${suffix}`.toUpperCase(),
      name: `Cliente smoke ${suffix}`,
      email: `cliente.${suffix}@example.test`,
      phone: '',
    },
  });

  const cashierUsername = `cajero.${suffix}`;
  const cashier = await api('/api/users', {
    method: 'POST',
    expected: [201],
    body: {
      username: cashierUsername,
      displayName: `Cajero smoke ${suffix}`,
      email: `${cashierUsername}@example.test`,
      roleIds: [cashierRole.id],
    },
  });
  const cashierTemporaryPassword = cashier.payload.data.temporaryPassword;
  const cashierFirstSession = await login(cashierUsername, cashierTemporaryPassword);
  if (!cashierFirstSession.data.user.mustChangePassword) {
    throw new Error('La cuenta creada no exige cambio inicial de contraseña.');
  }
  const cashierPassword = generatedPassword();
  await changePassword(cashierTemporaryPassword, cashierPassword);
  await login(cashierUsername, cashierTemporaryPassword, [400, 429]);
  const cashierSession = await login(cashierUsername, cashierPassword);
  if (!cashierSession.data.user.permissions.includes('VENTAS_CREAR')) {
    throw new Error('El Cajero no recibió VENTAS_CREAR.');
  }
  credentials.cashier = { username: cashierUsername, password: cashierPassword };
  await savePrivateAccess(credentials);

  await api('/api/audit/access?page=1&pageSize=25&search=&sort=date&direction=desc', {
    expected: [403],
  });
  await api('/api/me/preferences', { method: 'PUT', body: { theme: 'oscuro' } });
  const preference = await api('/api/me/preferences');
  if (preference.payload.data.theme !== 'oscuro') throw new Error('La preferencia Oscuro no persistió.');

  const saleLines = [{ productId: product.payload.data.id, quantity: 1 }];
  const quote = await api('/api/sales/quote', {
    method: 'POST',
    body: { customerId: customer.payload.data.id, lines: saleLines },
  });
  const totals = quote.payload.data.totals;
  if (totals.subtotal !== '100.00' || totals.tax !== '12.00' || totals.total !== '112.00') {
    throw new Error('La cotización 100.00 no produjo IVA 12.00 y total 112.00.');
  }

  const idempotencyKey = crypto.randomUUID();
  const saleBody = {
    customerId: customer.payload.data.id,
    lines: saleLines,
    acceptedTotal: totals.total,
    idempotencyKey,
  };
  const createdSale = await api('/api/sales', { method: 'POST', body: saleBody, expected: [201] });
  const replayedSale = await api('/api/sales', { method: 'POST', body: saleBody, expected: [200] });
  if (createdSale.payload.data.invoiceId !== replayedSale.payload.data.invoiceId) {
    throw new Error('El reintento idempotente devolvió otra factura.');
  }
  const invoiceId = createdSale.payload.data.invoiceId;
  const invoice = await api(`/api/sales/${invoiceId}`);
  if (
    invoice.payload.data.lines.length !== 1 ||
    invoice.payload.data.cashMovement?.amount !== '112.00' ||
    invoice.payload.data.total !== '112.00'
  ) {
    throw new Error('El comprobante no concuerda con detalle, caja y total esperado.');
  }
  const ownSales = await api('/api/sales?page=1&pageSize=25&search=&sort=date&direction=desc&scope=mine');
  if (!ownSales.payload.data.some((sale) => sale.id === invoiceId)) {
    throw new Error('La factura creada no aparece en ventas propias.');
  }

  await login(credentials.admin.username, adminPassword);
  const date = localDate(environment.TIME_ZONE || 'America/Guatemala');
  const report = await api(
    `/api/reports/sales?from=${date}&to=${date}&page=1&pageSize=25&search=&sort=date&direction=desc`,
  );
  if (!report.payload.data.some((sale) => sale.id === invoiceId)) {
    throw new Error('La factura confirmada no aparece en el reporte del día.');
  }

  evidence = {
    status: 'passed',
    startedAt: startedAt.toISOString(),
    finishedAt: new Date().toISOString(),
    database: environment.DB_NAME,
    origin: baseUrl,
    syntheticDataSuffix: suffix,
    invoiceId,
    checked: [
      'cambio inicial obligatorio y revocación de la clave temporal',
      'Administrador sin VENTAS_CREAR por defecto',
      'permisos de Cajero y rechazo de auditoría',
      'preferencia de tema por cuenta',
      'inventario y cotización SQL exacta 100.00/12.00/112.00',
      'venta, detalle, caja, ventas propias, reporte e idempotencia secuencial',
    ],
    checkpoints,
  };
} catch (error) {
  evidence = {
    status: 'failed',
    startedAt: startedAt.toISOString(),
    finishedAt: new Date().toISOString(),
    database: environment.DB_NAME,
    origin: baseUrl,
    error: error.message,
    checkpoints,
  };
  process.exitCode = 1;
} finally {
  await fs.mkdir(evidenceDirectory, { recursive: true });
  const stamp = startedAt.toISOString().replaceAll(/[:.]/gu, '-');
  const evidencePath = path.join(evidenceDirectory, `runtime-smoke-${stamp}.json`);
  await fs.writeFile(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
  console.info(`Smoke real: ${evidence.status}. Evidencia: ${path.relative(root, evidencePath)}`);
}
