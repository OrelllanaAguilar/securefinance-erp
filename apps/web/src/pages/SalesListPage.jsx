import { useCallback, useEffect, useState } from 'react';
import { Eye, PlusCircle, Search } from 'lucide-react';
import { Link } from 'react-router';
import { salesApi } from '../api/endpoints.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { EmptyState, ErrorState, PageHeader, PageLoader, Pagination, StatusBadge, TableWrap } from '../components/Ui.jsx';
import { entityId, firstDefined, formatDate, formatMoney, normalizeList } from '../utils/format.js';
import { hasPermission, PERMISSIONS } from '../utils/permissions.js';

export default function SalesListPage() {
  const { user } = useAuth();
  const canSell = hasPermission(user, PERMISSIONS.SELL);
  const canSeeAll = hasPermission(user, PERMISSIONS.REPORTS);
  const [filters, setFilters] = useState({ search: '', from: '', to: '', page: 1, pageSize: 25, scope: canSeeAll ? 'all' : 'mine' });
  const [query, setQuery] = useState(filters);
  const [state, setState] = useState({ status: 'loading', items: [], total: 0, error: null });

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await salesApi.list(query, signal);
      const items = normalizeList(response.data);
      setState({ status: 'ready', items, total: response.meta?.total ?? response.data?.total ?? items.length, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState((current) => ({ ...current, status: 'error', error }));
    }
  }, [query]);
  useEffect(() => { const controller = new AbortController(); load(controller.signal); return () => controller.abort(); }, [load]);

  const submit = (event) => { event.preventDefault(); const next = { ...filters, page: 1 }; setFilters(next); setQuery(next); };
  const page = (value) => { const next = { ...query, page: value }; setFilters(next); setQuery(next); };
  const pageSize = (value) => { const next = { ...query, page: 1, pageSize: value }; setFilters(next); setQuery(next); };
  const reload = () => setQuery((current) => ({ ...current }));

  return (
    <>
      <PageHeader title={canSeeAll ? 'Facturas' : 'Mis ventas'} description={canSeeAll ? 'Consulta las facturas autorizadas sin alterar sus datos históricos.' : 'Consulta únicamente las facturas procesadas por tu cuenta.'} actions={canSell && <Link className="button button--primary" to="/ventas/nueva"><PlusCircle size={18} /> Nueva venta</Link>} />
      <section className="panel">
        <form className="filter-bar filter-bar--wrap" onSubmit={submit} role="search">
          <div className="field field--grow"><label htmlFor="sale-search">Factura o cliente</label><div className="input-with-icon"><Search size={17} /><input id="sale-search" value={filters.search} maxLength="160" onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} /></div></div>
          <div className="field"><label htmlFor="sales-from">Desde</label><input id="sales-from" type="date" value={filters.from} onChange={(event) => setFilters((current) => ({ ...current, from: event.target.value }))} /></div>
          <div className="field"><label htmlFor="sales-to">Hasta</label><input id="sales-to" type="date" value={filters.to} onChange={(event) => setFilters((current) => ({ ...current, to: event.target.value }))} /></div>
          {canSeeAll && <div className="field"><label htmlFor="sales-scope">Alcance</label><select id="sales-scope" value={filters.scope} onChange={(event) => setFilters((current) => ({ ...current, scope: event.target.value }))}><option value="all">Todas</option><option value="mine">Propias</option></select></div>}
          <button className="button button--secondary" type="submit"><Search size={17} /> Aplicar</button>
        </form>
        {state.status === 'loading' && <PageLoader label="Cargando facturas…" />}
        {state.status === 'error' && <ErrorState error={state.error} onRetry={reload} />}
        {state.status === 'ready' && !state.items.length && <EmptyState search={Boolean(query.search || query.from || query.to)}>{query.search || query.from || query.to ? 'Ajusta los filtros para ampliar la búsqueda.' : 'Todavía no hay facturas disponibles.'}</EmptyState>}
        {state.status === 'ready' && state.items.length > 0 && <>
          <TableWrap label="Facturas"><table><thead><tr><th>Factura</th><th>Fecha</th><th>Cliente</th>{canSeeAll && <th>Cajero</th>}<th className="numeric">Total</th><th>Estado</th><th className="actions-cell">Acciones</th></tr></thead><tbody>
            {state.items.map((sale) => <tr key={entityId(sale)}>
              <td><Link className="table-link" to={`/ventas/${entityId(sale)}`}>{firstDefined(sale, ['number', 'invoiceNumber', 'numeroFactura'], entityId(sale))}</Link></td>
              <td className="nowrap">{formatDate(firstDefined(sale, ['issuedAt', 'createdAt', 'date', 'fecha']), { includeTime: true })}</td>
              <td>{firstDefined(sale, ['customerName', 'clienteNombre', 'customer'], 'Consumidor final')}</td>
              {canSeeAll && <td>{firstDefined(sale, ['cashierName', 'cajeroNombre', 'cashier'], '—')}</td>}
              <td className="numeric tabular"><strong>{formatMoney(firstDefined(sale, ['total'], '0.00'), firstDefined(sale, ['currency', 'moneda']))}</strong></td>
              <td><StatusBadge value={firstDefined(sale, ['status', 'estado'], 'Confirmada')} /></td>
              <td className="actions-cell"><Link className="icon-button" to={`/ventas/${entityId(sale)}`} aria-label={`Ver factura ${firstDefined(sale, ['number', 'invoiceNumber', 'numeroFactura'], entityId(sale))}`}><Eye size={17} /></Link></td>
            </tr>)}
          </tbody></table></TableWrap>
          <Pagination page={query.page} pageSize={query.pageSize} total={state.total} onPageChange={page} onPageSizeChange={pageSize} />
        </>}
      </section>
    </>
  );
}
