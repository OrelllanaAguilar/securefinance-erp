import { Navigate, useLocation } from 'react-router';
import { useAuth } from '../contexts/AuthContext.jsx';
import { hasPermission } from '../utils/permissions.js';
import { PageLoader } from './Ui.jsx';

export function PublicOnly({ children }) {
  const { status, forcePasswordChange } = useAuth();
  if (status === 'loading') return <PageLoader label="Comprobando sesión…" />;
  if (status === 'authenticated') return <Navigate replace to={forcePasswordChange ? '/perfil/seguridad' : '/inicio'} />;
  return children;
}

export function Protected({ children, permission, allowDuringPasswordChange = false }) {
  const { status, user, forcePasswordChange } = useAuth();
  const location = useLocation();
  if (status === 'loading') return <PageLoader label="Comprobando sesión…" />;
  if (status !== 'authenticated') return <Navigate replace to="/acceso" state={{ from: location }} />;
  if (forcePasswordChange && !allowDuringPasswordChange) return <Navigate replace to="/perfil/seguridad" />;
  if (!hasPermission(user, permission)) return <Navigate replace to="/sin-permiso" />;
  return children;
}

export function PasswordChangeBoundary({ children }) {
  const { status, forcePasswordChange } = useAuth();
  if (status === 'loading') return <PageLoader label="Comprobando sesión…" />;
  if (status === 'authenticated' && forcePasswordChange) return <Navigate replace to="/perfil/seguridad" />;
  return children;
}
