import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import ProfilePage from './ProfilePage.jsx';

const mocks = vi.hoisted(() => ({
  get: vi.fn(),
}));

vi.mock('../api/endpoints.js', () => ({
  meApi: { get: mocks.get },
}));

vi.mock('../components/ThemeSelector.jsx', () => ({
  ThemeSelector: () => <div>Selector de apariencia</div>,
}));

vi.mock('../contexts/AuthContext.jsx', async () => {
  const { useCallback, useState } = await import('react');
  return {
    useAuth: () => {
      const [user, setUser] = useState({ id: 7, username: 'admin.demo', displayName: 'Anterior' });
      const updateUser = useCallback((patch) => {
        setUser((current) => ({ ...current, ...patch }));
      }, []);
      return { user, updateUser };
    },
  };
});

describe('perfil', () => {
  it('consulta el perfil una sola vez aunque actualice el usuario global', async () => {
    mocks.get.mockResolvedValue({
      data: {
        id: 7,
        username: 'admin.demo',
        displayName: 'Administrador',
        email: 'admin@example.test',
        roles: ['Administrador'],
        permissions: ['USUARIOS_GESTIONAR'],
      },
    });

    render(<MemoryRouter><ProfilePage /></MemoryRouter>);

    expect(await screen.findByRole('heading', { name: 'Administrador' })).toBeInTheDocument();
    await waitFor(() => expect(mocks.get).toHaveBeenCalledTimes(1));
  });
});
