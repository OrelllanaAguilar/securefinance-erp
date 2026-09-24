import { buildQuery, request } from './client.js';

export const authApi = {
  session: (signal) => request('/api/auth/session', { signal }),
  login: (credentials) => request('/api/auth/login', { method: 'POST', body: credentials }),
  logout: () => request('/api/auth/logout', { method: 'POST' }),
  recover: (payload) => request('/api/auth/recover', { method: 'POST', body: payload }),
  reset: (payload) => request('/api/auth/reset', { method: 'POST', body: payload }),
};

export const meApi = {
  get: (signal) => request('/api/me', { signal }),
  getPreferences: (signal) => request('/api/me/preferences', { signal }),
  preferences: (payload) => request('/api/me/preferences', { method: 'PUT', body: payload }),
  password: (payload) => request('/api/me/password', { method: 'PUT', body: payload }),
};

export const dashboardApi = {
  get: (signal) => request('/api/dashboard', { signal }),
};

export const productsApi = {
  options: (signal) => request('/api/products/options', { signal }),
  list: (params, signal) => request(`/api/products${buildQuery(params)}`, { signal }),
  create: (payload) => request('/api/products', { method: 'POST', body: payload }),
  update: (id, payload) => request(`/api/products/${encodeURIComponent(id)}`, { method: 'PATCH', body: payload }),
  inventory: (id, payload) => request(`/api/products/${encodeURIComponent(id)}/inventory`, { method: 'POST', body: payload }),
};

export const customersApi = {
  list: (params, signal) => request(`/api/customers${buildQuery(params)}`, { signal }),
  create: (payload) => request('/api/customers', { method: 'POST', body: payload }),
  update: (id, payload) => request(`/api/customers/${encodeURIComponent(id)}`, { method: 'PATCH', body: payload }),
};

export const salesApi = {
  quote: (payload, signal) => request('/api/sales/quote', { method: 'POST', body: payload, signal }),
  create: (payload) => request('/api/sales', { method: 'POST', body: payload }),
  list: (params, signal) => request(`/api/sales${buildQuery(params)}`, { signal }),
  result: (key, signal) => request(`/api/sales/result/${encodeURIComponent(key)}`, { signal }),
  get: (id, signal) => request(`/api/sales/${encodeURIComponent(id)}`, { signal }),
};

export const reportsApi = {
  sales: (params, signal) => request(`/api/reports/sales${buildQuery(params)}`, { signal }),
};

export const auditApi = {
  list: (category, params, signal) => request(`/api/audit/${encodeURIComponent(category)}${buildQuery(params)}`, { signal }),
};

export const usersApi = {
  list: (params, signal) => request(`/api/users${buildQuery(params)}`, { signal }),
  create: (payload) => request('/api/users', { method: 'POST', body: payload }),
  update: (id, payload) => request(`/api/users/${encodeURIComponent(id)}`, { method: 'PATCH', body: payload }),
  resetPassword: (id) => request(`/api/users/${encodeURIComponent(id)}/reset-password`, { method: 'POST', body: {} }),
};

export const rolesApi = {
  list: (params, signal) => request(`/api/roles${buildQuery(params)}`, { signal }),
  create: (payload) => request('/api/roles', { method: 'POST', body: payload }),
  update: (id, payload) => request(`/api/roles/${encodeURIComponent(id)}`, { method: 'PATCH', body: payload }),
  permissions: (signal) => request('/api/permissions', { signal }),
};
