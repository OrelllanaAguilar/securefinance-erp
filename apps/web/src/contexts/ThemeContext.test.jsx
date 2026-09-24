import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ThemeProvider, useTheme } from './ThemeContext.jsx';

const mocks = vi.hoisted(() => ({
  auth: {
    status: 'anonymous',
    user: null,
    updateUser: vi.fn(),
  },
  preferences: vi.fn(),
  getPreferences: vi.fn(),
}));

vi.mock('./AuthContext.jsx', () => ({ useAuth: () => mocks.auth }));
vi.mock('../api/endpoints.js', () => ({
  meApi: {
    preferences: mocks.preferences,
    getPreferences: mocks.getPreferences,
  },
}));

function ThemeProbe() {
  const { preference, setPreference } = useTheme();
  return (
    <>
      <output aria-label="Preferencia">{preference}</output>
      <button type="button" onClick={() => setPreference('oscuro')}>Usar oscuro</button>
    </>
  );
}

describe('tema anónimo y por cuenta', () => {
  beforeEach(() => {
    localStorage.clear();
    mocks.auth.status = 'anonymous';
    mocks.auth.user = null;
    mocks.auth.forcePasswordChange = false;
    mocks.auth.updateUser = vi.fn();
    mocks.preferences.mockResolvedValue({ data: { theme: 'oscuro' } });
  });

  it('persiste la preferencia anónima solo en el navegador', async () => {
    localStorage.setItem('securefinance.anonymousTheme', 'claro');
    render(<ThemeProvider><ThemeProbe /></ThemeProvider>);

    expect(screen.getByLabelText('Preferencia')).toHaveTextContent('claro');
    fireEvent.click(screen.getByRole('button', { name: 'Usar oscuro' }));

    expect(localStorage.getItem('securefinance.anonymousTheme')).toBe('oscuro');
    expect(mocks.preferences).not.toHaveBeenCalled();
    await waitFor(() => expect(document.documentElement).toHaveAttribute('data-theme', 'dark'));
  });

  it('usa y guarda el tema de la cuenta sin sobrescribir el anónimo', async () => {
    localStorage.setItem('securefinance.anonymousTheme', 'sistema');
    mocks.auth.status = 'authenticated';
    mocks.auth.user = { id: 7, preferences: { theme: 'claro' } };
    render(<ThemeProvider><ThemeProbe /></ThemeProvider>);

    expect(screen.getByLabelText('Preferencia')).toHaveTextContent('claro');
    fireEvent.click(screen.getByRole('button', { name: 'Usar oscuro' }));

    await waitFor(() => expect(mocks.preferences).toHaveBeenCalledWith({ theme: 'oscuro' }));
    expect(localStorage.getItem('securefinance.anonymousTheme')).toBe('sistema');
  });

  it('cambia entre preferencias de cuentas y restaura la anónima al salir', async () => {
    localStorage.setItem('securefinance.anonymousTheme', 'sistema');
    mocks.auth.status = 'authenticated';
    mocks.auth.user = { id: 7, theme: 'claro' };
    const view = render(<ThemeProvider><ThemeProbe /></ThemeProvider>);
    expect(screen.getByLabelText('Preferencia')).toHaveTextContent('claro');

    mocks.auth.user = { id: 8, theme: 'oscuro' };
    view.rerender(<ThemeProvider><ThemeProbe /></ThemeProvider>);
    await waitFor(() => expect(screen.getByLabelText('Preferencia')).toHaveTextContent('oscuro'));

    mocks.auth.status = 'anonymous';
    mocks.auth.user = null;
    view.rerender(<ThemeProvider><ThemeProbe /></ThemeProvider>);
    await waitFor(() => expect(screen.getByLabelText('Preferencia')).toHaveTextContent('sistema'));
  });
});
