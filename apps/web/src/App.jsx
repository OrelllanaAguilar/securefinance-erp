import { Navigate, Route, Routes } from 'react-router';
import { AppShell } from './components/AppShell.jsx';
import { PasswordChangeBoundary, Protected, PublicOnly } from './components/RouteGuards.jsx';
import { PERMISSIONS } from './utils/permissions.js';
import LoginPage from './pages/LoginPage.jsx';
import RecoveryPage from './pages/RecoveryPage.jsx';
import ResetPage from './pages/ResetPage.jsx';
import DashboardPage from './pages/DashboardPage.jsx';
import SalesListPage from './pages/SalesListPage.jsx';
import SaleNewPage from './pages/SaleNewPage.jsx';
import SaleDetailPage from './pages/SaleDetailPage.jsx';
import ProductsPage from './pages/ProductsPage.jsx';
import CustomersPage from './pages/CustomersPage.jsx';
import SalesReportPage from './pages/SalesReportPage.jsx';
import AuditPage from './pages/AuditPage.jsx';
import UsersPage from './pages/UsersPage.jsx';
import RolesPage from './pages/RolesPage.jsx';
import ProfilePage from './pages/ProfilePage.jsx';
import SecurityPage from './pages/SecurityPage.jsx';
import { ForbiddenPage, NotFoundPage } from './pages/SystemPages.jsx';

function privatePage(element, permission, allowDuringPasswordChange = false) {
  return <Protected permission={permission} allowDuringPasswordChange={allowDuringPasswordChange}>{element}</Protected>;
}

export default function App() {
  return (
    <Routes>
      <Route path="/acceso" element={<PublicOnly><LoginPage /></PublicOnly>} />
      <Route path="/recuperar" element={<PublicOnly><RecoveryPage /></PublicOnly>} />
      <Route path="/restablecer" element={<PublicOnly><ResetPage /></PublicOnly>} />

      <Route element={privatePage(<AppShell />, undefined, true)}>
        <Route path="/inicio" element={privatePage(<DashboardPage />)} />
        <Route path="/ventas/nueva" element={privatePage(<SaleNewPage />, PERMISSIONS.SELL)} />
        <Route path="/ventas" element={privatePage(<SalesListPage />, [PERMISSIONS.SELL, PERMISSIONS.REPORTS])} />
        <Route path="/ventas/:id" element={privatePage(<SaleDetailPage />, [PERMISSIONS.SELL, PERMISSIONS.REPORTS])} />
        <Route path="/productos" element={privatePage(<ProductsPage />, [PERMISSIONS.SELL, PERMISSIONS.PRODUCTS])} />
        <Route path="/clientes" element={privatePage(<CustomersPage />, [PERMISSIONS.SELL, PERMISSIONS.CUSTOMERS])} />
        <Route path="/reportes/ventas" element={privatePage(<SalesReportPage />, PERMISSIONS.REPORTS)} />
        <Route path="/auditoria" element={privatePage(<AuditPage />, PERMISSIONS.AUDIT)} />
        <Route path="/usuarios" element={privatePage(<UsersPage />, PERMISSIONS.USERS)} />
        <Route path="/roles" element={privatePage(<RolesPage />, PERMISSIONS.ROLES)} />
        <Route path="/perfil" element={privatePage(<ProfilePage />)} />
        <Route path="/perfil/seguridad" element={privatePage(<SecurityPage />, undefined, true)} />
        <Route path="/sin-permiso" element={privatePage(<ForbiddenPage />)} />
      </Route>

      <Route path="/" element={<Navigate replace to="/inicio" />} />
      <Route path="*" element={<PasswordChangeBoundary><NotFoundPage /></PasswordChangeBoundary>} />
    </Routes>
  );
}
