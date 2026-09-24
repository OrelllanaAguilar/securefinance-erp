import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const ROUTES = [
  { path: '/acceso', heading: 'Acceder' },
  { path: '/recuperar', heading: 'Recuperar acceso' },
  { path: '/restablecer?token=token-de-prueba', heading: 'Restablecer contraseña', clearsToken: true },
];
const THEMES = [
  { preference: 'claro', resolved: 'light' },
  { preference: 'oscuro', resolved: 'dark' },
];
const VIEWPORTS = [
  { label: '320', width: 320, height: 720 },
  { label: '768', width: 768, height: 900 },
  { label: '1280', width: 1280, height: 900 },
];

async function preparePublicPage(page, preference) {
  const browserErrors = [];
  page.on('console', (message) => {
    if (message.type() === 'error') browserErrors.push(`console: ${message.text()}`);
  });
  page.on('pageerror', (error) => browserErrors.push(`page: ${error.message}`));
  await page.route('**/api/auth/session', (route) => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ data: { authenticated: false } }),
  }));
  await page.addInitScript((theme) => {
    localStorage.setItem('securefinance.anonymousTheme', theme);
  }, preference);
  return browserErrors;
}

for (const route of ROUTES) {
  for (const theme of THEMES) {
    for (const viewport of VIEWPORTS) {
      test(`${route.heading} · ${theme.preference} · ${viewport.label}px`, async ({ page }) => {
        const browserErrors = await preparePublicPage(page, theme.preference);
        await page.setViewportSize(viewport);
        await page.goto(route.path);

        await expect(page.getByRole('heading', { level: 1, name: route.heading })).toBeVisible();
        await expect(page.locator('html')).toHaveAttribute('data-theme', theme.resolved);
        await expect(page.locator('html')).toHaveAttribute('data-theme-preference', theme.preference);
        await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);

        if (route.clearsToken) {
          await expect(page).toHaveURL(/\/restablecer$/);
          await expect(page.locator('#token')).toHaveCount(0);
        }

        const accessibility = await new AxeBuilder({ page }).analyze();
        expect(accessibility.violations, accessibility.violations.map((item) => `${item.id}: ${item.help}`).join('\n')).toEqual([]);
        expect(browserErrors).toEqual([]);
      });
    }
  }
}

test('la política CSP admite el inicializador externo de tema', async ({ page }) => {
  const browserErrors = await preparePublicPage(page, 'oscuro');
  await page.goto('/acceso');

  const policy = await page.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute('content');
  expect(policy).toContain("script-src 'self'");
  expect(policy).not.toContain("'unsafe-inline'");
  await expect(page.locator('script[src="/theme-init.js"]')).toHaveCount(1);
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  expect(browserErrors).toEqual([]);
});
