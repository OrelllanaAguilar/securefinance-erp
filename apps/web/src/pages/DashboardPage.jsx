import { useCallback, useEffect, useState } from 'react';
import { ArrowRight, BadgeDollarSign, Boxes, ChartNoAxesCombined, PlusCircle, RefreshCw, UsersRound } from 'lucide-react';
import { Link } from 'react-router';
import { dashboardApi } from '../api/endpoints.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { EmptyState, InlineAlert, PageHeader, PageLoader } from '../components/Ui.jsx';
import { errorMessage } from '../api/client.js';
import { formatDate, formatMoney, firstDefined } from '../utils/format.js';
import { hasPermission, PERMISSIONS } from '../utils/permissions.js';

export default function DashboardPage() {
  const { user } = useAuth();
  const [state, setState] = useState({ status: 'loading', data: null, error: null });
  const canReport = hasPermission(user, PERMISSIONS.REPORTS);

  const load = useCallback(async (signal) => {
    setState({ status: 'loading', data: null, error: null });
    try {
      const response = await dashboardApi.get(signal);
      setState({ status: 'ready', data: response.data || {}, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState({ status: 'error', data: null, error });
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const displayName = user?.displayName || user?.name || user?.nombreCompleto || user?.username || 'usuario';

  return (
    <>
      <PageHeader
        title={`Hola, ${displayName}`}
        description="Accede a tus tareas autorizadas y revisa la actividad disponible."
        actions={<button type="button" className="button button--secondary" onClick={() => load()} disabled={state.status === 'loading'}><RefreshCw size={17} /> Actualizar</button>}
      />
      {state.status === 'loading' && <PageLoader label="Preparando el inicio…" />}
      {state.status === 'error' && <InlineAlert variant="error" title="No se pudo cargar el resumen" onRetry={() => load()}>{errorMessage(state.error)} Los accesos autorizados siguen disponibles.</InlineAlert>}
      {state.status !== 'loading' && (
        <div className="dashboard-grid">
          {canReport && state.status === 'ready' && state.data.summary && (
            <section className="panel panel--span" aria-labelledby="today-title">
              <div className="panel__header">
                <div><p className="eyebrow">Resumen autorizado</p><h2 id="today-title">Ventas de hoy</h2>{state.data.refreshedAt && <small className="muted">Actualizado: {formatDate(state.data.refreshedAt, { includeTime: true })}</small>}</div>
                <Link to="/reportes/ventas" className="text-link">Ver reporte <ArrowRight size={16} /></Link>
              </div>
              <div className="metric-row">
                <div className="metric"><span>Facturas</span><strong>{firstDefined(state.data.summary, ['saleCount', 'salesCount', 'invoiceCount', 'cantidadVentas'], '0')}</strong></div>
                <div className="metric"><span>Total</span><strong>{formatMoney(firstDefined(state.data.summary, ['total', 'salesTotal', 'totalVentas'], '0.00'), firstDefined(state.data.summary, ['currency', 'moneda']))}</strong></div>
                {firstDefined(state.data.summary, ['averageTicket', 'ticketPromedio'], null) !== null && <div className="metric"><span>Promedio</span><strong>{formatMoney(firstDefined(state.data.summary, ['averageTicket', 'ticketPromedio']), firstDefined(state.data.summary, ['currency', 'moneda']))}</strong></div>}
              </div>
            </section>
          )}

          <section className="panel panel--span" aria-labelledby="shortcuts-title">
            <div className="panel__header"><div><p className="eyebrow">Trabajo</p><h2 id="shortcuts-title">Accesos rápidos</h2></div></div>
            <div className="shortcut-grid">
              {hasPermission(user, PERMISSIONS.SELL) && <Shortcut to="/ventas/nueva" icon={PlusCircle} title="Nueva venta" description="Cotiza y confirma una venta transaccional." />}
              {hasPermission(user, [PERMISSIONS.SELL, PERMISSIONS.REPORTS]) && <Shortcut to="/ventas" icon={BadgeDollarSign} title="Facturas" description={hasPermission(user, PERMISSIONS.REPORTS) ? 'Consulta las facturas autorizadas.' : 'Consulta tus propias facturas.'} />}
              {hasPermission(user, [PERMISSIONS.SELL, PERMISSIONS.PRODUCTS]) && <Shortcut to="/productos" icon={Boxes} title="Productos" description="Consulta disponibilidad y catálogo." />}
              {hasPermission(user, [PERMISSIONS.SELL, PERMISSIONS.CUSTOMERS]) && <Shortcut to="/clientes" icon={UsersRound} title="Clientes" description="Busca clientes activos." />}
              {canReport && <Shortcut to="/reportes/ventas" icon={ChartNoAxesCombined} title="Reporte de ventas" description="Filtra resultados y totales del período." />}
            </div>
            {!hasPermission(user, [PERMISSIONS.SELL, PERMISSIONS.REPORTS, PERMISSIONS.PRODUCTS, PERMISSIONS.CUSTOMERS]) && (
              <EmptyState title="Sin módulos adicionales">Tu cuenta conserva las funciones personales de perfil, apariencia y seguridad.</EmptyState>
            )}
          </section>
        </div>
      )}
    </>
  );
}

function Shortcut({ to, icon: Icon, title, description }) {
  return (
    <Link to={to} className="shortcut">
      <span className="shortcut__icon"><Icon size={20} aria-hidden="true" /></span>
      <span><strong>{title}</strong><small>{description}</small></span>
      <ArrowRight size={17} aria-hidden="true" />
    </Link>
  );
}
