import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { AppShell } from './AppShell.jsx';

const mocks = vi.hoisted(() => ({
  logout: vi.fn().mockResolvedValue(undefined),
  auth: {
    user: { displayName: 'Cuenta temporal', permissions: [] },
    forcePasswordChange: true,
  },
}));

vi.mock('../contexts/AuthContext.jsx', () => ({
  useAuth: () => ({ ...mocks.auth, logout: mocks.logout }),
}));
vi.mock('./ThemeSelector.jsx', () => ({ ThemeSelector: () => <div>Selector de tema</div> }));

describe('shell durante el cambio obligatorio de contraseña', () => {
  it('expone seguridad, cierre y el cambio local de apariencia', async () => {
    const user = userEvent.setup();
    render(
      <MemoryRouter initialEntries={['/perfil/seguridad']}>
        <Routes>
          <Route element={<AppShell />}>
            <Route path="/perfil/seguridad" element={<p>Formulario de seguridad</p>} />
          </Route>
          <Route path="/acceso" element={<p>Página de acceso</p>} />
        </Routes>
      </MemoryRouter>,
    );

    const navigation = screen.getByRole('navigation');
    expect(within(navigation).getAllByRole('link')).toHaveLength(1);
    expect(within(navigation).getByRole('link', { name: 'Seguridad' })).toBeInTheDocument();
    expect(screen.getByText('Selector de tema')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Cuenta temporal/ }));
    expect(screen.getByRole('menuitem', { name: 'Cerrar sesión' })).toBeInTheDocument();
    expect(screen.queryByRole('menuitem', { name: 'Mi perfil' })).not.toBeInTheDocument();
  });
});
