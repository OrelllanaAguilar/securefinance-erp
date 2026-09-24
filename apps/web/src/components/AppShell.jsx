import { useState } from 'react';
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router';
import {
  BadgeDollarSign,
  Boxes,
  ChartNoAxesCombined,
  ChevronDown,
  ClipboardList,
  FileClock,
  Home,
  LogOut,
  Menu,
  PlusCircle,
  ShieldCheck,
  UserRound,
  Users,
  UsersRound,
  X,
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext.jsx';
import { ThemeSelector } from './ThemeSelector.jsx';
import { hasPermission, PERMISSIONS } from '../utils/permissions.js';

const navigation = [
  { to: '/inicio', label: 'Inicio', icon: Home },
  { to: '/ventas/nueva', label: 'Nueva venta', icon: PlusCircle, permission: PERMISSIONS.SELL },
  { to: '/ventas', label: 'Facturas', icon: BadgeDollarSign, permission: [PERMISSIONS.SELL, PERMISSIONS.REPORTS] },
  { to: '/productos', label: 'Productos', icon: Boxes, permission: [PERMISSIONS.SELL, PERMISSIONS.PRODUCTS] },
  { to: '/clientes', label: 'Clientes', icon: UsersRound, permission: [PERMISSIONS.SELL, PERMISSIONS.CUSTOMERS] },
  { to: '/reportes/ventas', label: 'Reportes', icon: ChartNoAxesCombined, permission: PERMISSIONS.REPORTS },
  { to: '/auditoria', label: 'Auditoría', icon: FileClock, permission: PERMISSIONS.AUDIT },
  { to: '/usuarios', label: 'Usuarios', icon: Users, permission: PERMISSIONS.USERS },
  { to: '/roles', label: 'Roles y permisos', icon: ShieldCheck, permission: PERMISSIONS.ROLES },
];

function displayName(user) {
  return user?.displayName || user?.name || user?.nombreCompleto || user?.username || user?.usuario || 'Mi cuenta';
}

export function AppShell() {
  const { user, logout, forcePasswordChange } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [menuOpen, setMenuOpen] = useState(false);
  const [accountOpen, setAccountOpen] = useState(false);
  const homeTarget = forcePasswordChange ? '/perfil/seguridad' : '/inicio';

  const closeMenu = () => setMenuOpen(false);
  const signOut = async () => {
    await logout();
    navigate('/acceso', { replace: true });
  };

  return (
    <div className="app-layout">
      <a className="skip-link" href="#main-content">Saltar al contenido</a>
      <header className="topbar">
        <button type="button" className="icon-button mobile-menu-button" onClick={() => setMenuOpen(true)} aria-label="Abrir menú" aria-expanded={menuOpen}>
          <Menu aria-hidden="true" />
        </button>
        <NavLink to={homeTarget} className="brand brand--top" aria-label="SecureFinance ERP">
          <span className="brand__mark">SF</span>
          <span>SecureFinance</span>
        </NavLink>
        <div className="topbar__actions">
          <ThemeSelector compact />
          <div className="account-menu">
            <button
              type="button"
              className="account-button"
              onClick={() => setAccountOpen((value) => !value)}
              aria-label={`Menú de cuenta de ${displayName(user)}`}
              aria-expanded={accountOpen}
              aria-haspopup="menu"
            >
              <span className="account-avatar" aria-hidden="true"><UserRound size={17} /></span>
              <span className="account-button__label">{displayName(user)}</span>
              <ChevronDown size={16} aria-hidden="true" />
            </button>
            {accountOpen && (
              <div className="account-popover" role="menu">
                {!forcePasswordChange && <NavLink to="/perfil" role="menuitem" onClick={() => setAccountOpen(false)}><UserRound size={16} /> Mi perfil</NavLink>}
                <NavLink to="/perfil/seguridad" role="menuitem" onClick={() => setAccountOpen(false)}><ShieldCheck size={16} /> Seguridad</NavLink>
                <button type="button" role="menuitem" onClick={signOut}><LogOut size={16} /> Cerrar sesión</button>
              </div>
            )}
          </div>
        </div>
      </header>

      {menuOpen && <button type="button" className="nav-scrim" aria-label="Cerrar menú" onClick={closeMenu} />}
      <aside className={`sidebar ${menuOpen ? 'sidebar--open' : ''}`} aria-label="Navegación principal">
        <div className="sidebar__header">
          <NavLink to={homeTarget} className="brand" onClick={closeMenu}>
            <span className="brand__mark">SF</span>
            <span><strong>SecureFinance</strong><small>ERP local</small></span>
          </NavLink>
          <button type="button" className="icon-button sidebar__close" onClick={closeMenu} aria-label="Cerrar menú"><X /></button>
        </div>
        <nav className="sidebar__nav">
          {forcePasswordChange ? (
            <NavLink to="/perfil/seguridad" onClick={closeMenu}><ShieldCheck aria-hidden="true" size={19} /><span>Seguridad</span></NavLink>
          ) : navigation.filter((item) => hasPermission(user, item.permission)).map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              onClick={closeMenu}
              className={({ isActive }) => (isActive || (to === '/ventas' && location.pathname.startsWith('/ventas/') && location.pathname !== '/ventas/nueva') ? 'active' : undefined)}
            >
              <Icon aria-hidden="true" size={19} />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>
        <div className="sidebar__footer">
          <ClipboardList aria-hidden="true" size={17} />
          <span>Operaciones auditadas</span>
        </div>
      </aside>

      <main id="main-content" className="main-content" tabIndex="-1">
        <Outlet />
      </main>
    </div>
  );
}
