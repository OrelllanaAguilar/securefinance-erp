import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const credentialsPath = path.join(repositoryRoot, 'secrets', 'test-current-access.json');
const environmentPath = path.join(repositoryRoot, '.env');
const runtimeEvidenceDirectory = path.join(repositoryRoot, 'docs', 'evidence', 'runtime');
const screenshotDirectory = path.join(runtimeEvidenceDirectory, 'ui');

const ADMIN_ROUTES = [
  ['inicio', '/inicio'],
  ['productos', '/productos'],
  ['clientes', '/clientes'],
  ['reportes', '/reportes/ventas'],
  ['auditoria', '/auditoria'],
  ['usuarios', '/usuarios'],
  ['roles', '/roles'],
  ['perfil', '/perfil'],
];

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

async function latestPassedEvidence(databaseName) {
  const files = (await fs.readdir(runtimeEvidenceDirectory))
    .filter((name) => /^runtime-smoke-.+\.json$/u.test(name))
    .sort()
    .reverse();
  for (const name of files) {
    const evidence = JSON.parse(await fs.readFile(path.join(runtimeEvidenceDirectory, name), 'utf8'));
    if (evidence.status === 'passed' && evidence.database === databaseName && evidence.invoiceId) return evidence;
  }
  throw new Error('No existe una evidencia smoke aprobada con factura sintética.');
}

async function signIn(page, credentials) {
  await page.goto('/acceso');
  await page.getByLabel('Usuario').fill(credentials.username);
  await page.locator('#password').fill(credentials.password);
  await page.getByRole('button', { name: 'Acceder' }).click();
  await expect(page).toHaveURL(/\/inicio$/u);
}

async function signOut(page) {
  await page.locator('.account-button').click();
  await page.getByRole('menuitem', { name: 'Cerrar sesión' }).click();
  await expect(page).toHaveURL(/\/acceso$/u);
}

async function selectTheme(page, preference, resolved) {
  await page.locator('#theme-compact').selectOption(preference);
  await expect(page.locator('html')).toHaveAttribute('data-theme', resolved);
  await expect(page.locator('html')).toHaveAttribute('data-theme-preference', preference);
}

async function captureRoute(page, browserErrors, { account, label, route, theme, viewport }) {
  browserErrors.length = 0;
  await page.setViewportSize(viewport);
  await page.goto(route);
  await expect(page.locator('main h1')).toBeVisible();
  if (route === '/perfil') await expect(page.getByText('Acceso efectivo')).toBeVisible();
  await expect(page).toHaveURL(new RegExp(`${route.replaceAll('/', '\\/')}$`, 'u'));
  const resolvedTheme = theme === 'oscuro' ? 'dark' : 'light';
  const expectedHeadingColor = resolvedTheme === 'dark' ? 'rgb(245, 243, 237)' : 'rgb(35, 35, 35)';
  await expect(page.locator('html')).toHaveAttribute('data-theme', resolvedTheme);
  await expect.poll(() => page.locator('main h1').evaluate((heading) => getComputedStyle(heading).color))
    .toBe(expectedHeadingColor);
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(
    accessibility.violations,
    accessibility.violations.map((item) => `${item.id}: ${item.help}`).join('\n'),
  ).toEqual([]);
  expect(browserErrors).toEqual([]);

  await page.screenshot({
    path: path.join(screenshotDirectory, `${account}-${label}-${theme}-${viewport.width}.png`),
    fullPage: true,
    animations: 'disabled',
    mask: [
      page.locator('.account-button'),
      page.locator('tbody'),
      page.locator('.receipt__meta'),
      page.locator('.details-list dd'),
      page.locator('.selected-entity'),
    ],
  });
}

async function verifyInventoryAdjustment(page, syntheticDataSuffix) {
  const code = `SMK-${syntheticDataSuffix}`.toUpperCase();
  await page.goto('/productos');
  await page.locator('#product-search').fill(code);
  await page.getByRole('button', { name: 'Buscar' }).click();
  const row = page.getByRole('row').filter({ hasText: code });
  await expect(row).toHaveCount(1);
  const stockCell = row.locator('td').nth(4);
  const previousStock = Number((await stockCell.textContent())?.trim());
  expect(Number.isInteger(previousStock)).toBe(true);

  await row.getByRole('button', { name: /Ajustar inventario/u }).click();
  await page.locator('#quantity-change').fill('1');
  await page.locator('#inventory-reason').fill('Comprobación automática del ajuste de inventario');
  const responsePromise = page.waitForResponse((response) => (
    response.request().method() === 'POST'
    && /\/api\/products\/\d+\/inventory$/u.test(new URL(response.url()).pathname)
  ));
  await page.getByRole('button', { name: 'Aplicar ajuste' }).click();
  const response = await responsePromise;
  expect(response.status()).toBe(200);
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(stockCell).toHaveText(String(previousStock + 1));
}

test('recorrido privado real, accesible y sin errores del navegador', async ({ page }) => {
  const environment = parseEnvironment(await fs.readFile(environmentPath, 'utf8'));
  expect(environment.DB_NAME).toMatch(/_Test$/u);
  const credentials = JSON.parse(await fs.readFile(credentialsPath, 'utf8'));
  expect(credentials.database).toBe(environment.DB_NAME);
  expect(credentials).toMatchObject({
    admin: { username: expect.any(String), password: expect.any(String) },
    cashier: { username: expect.any(String), password: expect.any(String) },
  });
  const evidence = await latestPassedEvidence(environment.DB_NAME);
  const invoiceId = evidence.invoiceId;
  expect(evidence.syntheticDataSuffix).toEqual(expect.any(String));
  await fs.mkdir(screenshotDirectory, { recursive: true });

  const browserErrors = [];
  page.on('console', (message) => {
    if (message.type() === 'error') browserErrors.push(`console: ${message.text()}`);
  });
  page.on('pageerror', (error) => browserErrors.push(`page: ${error.message}`));
  let profileRequests = 0;
  page.on('request', (request) => {
    if (request.method() === 'GET' && new URL(request.url()).pathname === '/api/me') profileRequests += 1;
  });

  await signIn(page, credentials.admin);
  await selectTheme(page, 'claro', 'light');
  await verifyInventoryAdjustment(page, evidence.syntheticDataSuffix);
  for (const [label, route] of ADMIN_ROUTES) {
    await captureRoute(page, browserErrors, {
      account: 'admin',
      label,
      route,
      theme: 'claro',
      viewport: { width: 1440, height: 900 },
    });
  }
  await page.waitForTimeout(500);
  expect(profileRequests).toBe(1);
  await signOut(page);

  await signIn(page, credentials.cashier);
  await selectTheme(page, 'oscuro', 'dark');
  const cashierRoutes = [
    ['inicio', '/inicio'],
    ['nueva-venta', '/ventas/nueva'],
    ['facturas', '/ventas'],
    ['comprobante', `/ventas/${invoiceId}`],
    ['productos', '/productos'],
    ['clientes', '/clientes'],
  ];
  for (const [label, route] of cashierRoutes) {
    await captureRoute(page, browserErrors, {
      account: 'cajero',
      label,
      route,
      theme: 'oscuro',
      viewport: { width: 390, height: 844 },
    });
  }
  await signOut(page);
});
