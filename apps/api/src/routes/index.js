import { Router } from 'express';
import { createAdminHealthRouter } from './system.js';
import { createAuthRouter } from './auth.js';
import { createMeRouter } from './me.js';
import { createDashboardRouter } from './dashboard.js';
import { createProductsRouter, createCustomersRouter } from './catalogs.js';
import { createSalesRouter } from './sales.js';
import { createReportsRouter } from './reports.js';
import { createAuditRouter } from './audit.js';
import {
  createPermissionsRouter,
  createRolesRouter,
  createUsersRouter,
} from './admin.js';
import { notFoundHandler } from '../middleware/errors.js';

export function createApiRouter() {
  const router = Router();
  router.use('/health', createAdminHealthRouter());
  router.use('/auth', createAuthRouter());
  router.use('/me', createMeRouter());
  router.use('/dashboard', createDashboardRouter());
  router.use('/products', createProductsRouter());
  router.use('/customers', createCustomersRouter());
  router.use('/sales', createSalesRouter());
  router.use('/reports', createReportsRouter());
  router.use('/audit', createAuditRouter());
  router.use('/users', createUsersRouter());
  router.use('/roles', createRolesRouter());
  router.use('/permissions', createPermissionsRouter());
  router.use(notFoundHandler);
  return router;
}
