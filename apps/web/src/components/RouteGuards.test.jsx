import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PasswordChangeBoundary, Protected } from './RouteGuards.jsx';

const mocks = vi.hoisted(() => ({
  auth: { status: 'anonymous', user: null, forcePasswordChange: false },
}));

vi.mock('../contexts/AuthContext.jsx', () => ({ useAuth: () => mocks.auth }));

function renderRoutes(initialEntry, element) {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <Routes>
        <Route path="/acceso" element={<p>Acceso</p>} />
        <Route path="/perfil/seguridad" element={<p>Seguridad</p>} />
        <Route path="/sin-permiso" element={<p>Sin permiso</p>} />
        <Route path="*" element={element} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('navegación protegida', () => {
  beforeEach(() => {
    mocks.auth.status = 'anonymous';
    mocks.auth.user = null;
    mocks.auth.forcePasswordChange = false;
  });

  it('envía una ruta privada anónima al acceso', () => {
    renderRoutes('/inicio', <Protected><p>Privado</p></Protected>);
    expect(screen.getByText('Acceso')).toBeInTheDocument();
    expect(screen.queryByText('Privado')).not.toBeInTheDocument();
  });

  it('limita una sesión con cambio obligatorio a seguridad', () => {
    mocks.auth.status = 'authenticated';
    mocks.auth.user = { permissions: ['VENTAS_CREAR'] };
    mocks.auth.forcePasswordChange = true;
    renderRoutes('/ventas/nueva', <Protected permission="VENTAS_CREAR"><p>Nueva venta</p></Protected>);
    expect(screen.getByText('Seguridad')).toBeInTheDocument();
  });

  it('permite la página de seguridad durante el cambio obligatorio', () => {
    mocks.auth.status = 'authenticated';
    mocks.auth.user = { permissions: [] };
    mocks.auth.forcePasswordChange = true;
    renderRoutes('/seguridad-form', <Protected allowDuringPasswordChange><p>Formulario seguro</p></Protected>);
    expect(screen.getByText('Formulario seguro')).toBeInTheDocument();
  });

  it('impide que una ruta desconocida evada el cambio obligatorio', () => {
    mocks.auth.status = 'authenticated';
    mocks.auth.user = { permissions: [] };
    mocks.auth.forcePasswordChange = true;
    renderRoutes('/ruta-inexistente', <PasswordChangeBoundary><p>No encontrada</p></PasswordChangeBoundary>);
    expect(screen.getByText('Seguridad')).toBeInTheDocument();
  });
});
