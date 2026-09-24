import { useCallback, useEffect, useMemo, useState } from 'react';
import { Eye, Printer, Search } from 'lucide-react';
import { Link } from 'react-router';
import { reportsApi } from '../api/endpoints.js';
import { EmptyState, ErrorState, FieldError, PageHeader, PageLoader, Pagination, TableWrap } from '../components/Ui.jsx';
import { configuredDateInput, entityId, firstDefined, formatDate, formatMoney, normalizeList } from '../utils/format.js';

function initialRange() {
  return { from: configuredDateInput(-29), to: configuredDateInput() };
}

function rangeError(from, to) {
  if (!from || !to) return 'Selecciona ambas fechas.';
  const days = (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000;
  if (!Number.isFinite(days) || days < 0) return 'La fecha final debe ser igual o posterior a la inicial.';
  if (days > 365) return 'El intervalo máximo es de 366 días inclusivos.';
  return '';
}

export default function SalesReportPage() {
  const range = useMemo(initialRange, []);
  const [filters, setFilters] = useState({ ...range, search: '', sort: 'date', direction: 'desc', page: 1, pageSize: 25 });
  const [query, setQuery] = useState(filters);
  const [validation, setValidation] = useState('');
  const [state, setState] = useState({ status: 'loading', items: [], meta: null, error: null });

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await reportsApi.sales(query, signal);
      setState({ status: 'ready', items: normalizeList(response.data), meta: response.meta || {}, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState((current) => ({ ...current, status: 'error', error }));
    }
  }, [query]);

  useEffect(() => { const controller = new AbortController(); load(controller.signal); return () => controller.abort(); }, [load]);

  const submit = (event) => {
    event.preventDefault();
    const issue = rangeError(filters.from, filters.to);
    setValidation(issue);
    if (issue) return;
    const next = { ...filters, page: 1 };
    setFilters(next); setQuery(next);
  };
  const page = (value) => { const next = { ...query, page: value }; setFilters(next); setQuery(next); };
  const pageSize = (value) => { const next = { ...query, page: 1, pageSize: value }; setFilters(next); setQuery(next); };
  const reload = () => setQuery((current) => ({ ...current }));
  const totals = state.meta?.totals || {};
  const currency = firstDefined(totals, ['currency', 'moneda']);

  return (
    <>
      <PageHeader title="Reporte de ventas" description="Los totales corresponden al filtro completo, no solo a la página visible." actions={state.status === 'ready' && state.items.length > 0 && <button type="button" className="button button--secondary print-hidden" onClick={() => window.print()}><Printer size={17} /> Imprimir</button>} />
      <section className="panel report-panel">
        <form className="filter-bar filter-bar--wrap print-hidden" onSubmit={submit} role="search">
          <div className="field"><label htmlFor="report-from">Desde</label><input id="report-from" type="date" required value={filters.from} onChange={(event) => setFilters((current) => ({ ...current, from: event.target.value }))} aria-invalid={validation ? 'true' : undefined} /></div>
          <div className="field"><label htmlFor="report-to">Hasta</label><input id="report-to" type="date" required value={filters.to} onChange={(event) => setFilters((current) => ({ ...current, to: event.target.value }))} aria-invalid={validation ? 'true' : undefined} aria-describedby="report-range-error" /><FieldError id="report-range-error" error={validation} /></div>
          <div className="field field--grow"><label htmlFor="report-search">Factura, cliente o cajero</label><div className="input-with-icon"><Search size={17} /><input id="report-search" value={filters.search} onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} maxLength="160" /></div></div>
          <div className="field"><label htmlFor="report-sort">Ordenar por</label><select id="report-sort" value={filters.sort} onChange={(event) => setFilters((current) => ({ ...current, sort: event.target.value }))}><option value="date">Fecha</option><option value="number">Factura</option><option value="customer">Cliente</option><option value="cashier">Cajero</option><option value="total">Total</option></select></div>
          <button type="submit" className="button button--secondary"><Search size={17} /> Consultar</button>
        </form>
        {state.status === 'loading' && <PageLoader label="Calculando reporte…" />}
        {state.status === 'error' && <ErrorState error={state.error} onRetry={reload} title="No se pudo generar el reporte" />}
        {state.status === 'ready' && <>
          <section className="report-summary" aria-label="Totales del reporte">
            <div><span>Facturas</span><strong>{firstDefined(totals, ['count', 'invoiceCount', 'cantidadFacturas'], state.meta?.total ?? '0')}</strong></div>
            <div><span>Subtotal</span><strong>{formatMoney(firstDefined(totals, ['subtotal'], '0.00'), currency)}</strong></div>
            <div><span>IVA</span><strong>{formatMoney(firstDefined(totals, ['tax', 'iva'], '0.00'), currency)}</strong></div>
            <div className="report-summary__total"><span>Total</span><strong>{formatMoney(firstDefined(totals, ['total'], '0.00'), currency)}</strong></div>
          </section>
          {!state.items.length ? <EmptyState search title="Sin ventas en el período">No hay facturas que coincidan con los filtros seleccionados.</EmptyState> : <>
            <TableWrap label="Resultados del reporte de ventas"><table><thead><tr><th>Factura</th><th>Fecha</th><th>Cliente</th><th>Cajero</th><th className="numeric">Subtotal</th><th className="numeric">IVA</th><th className="numeric">Total</th><th className="actions-cell print-hidden">Ver</th></tr></thead><tbody>
              {state.items.map((sale) => <tr key={entityId(sale)}><td><Link className="table-link" to={`/ventas/${entityId(sale)}`}>{firstDefined(sale, ['number', 'invoiceNumber', 'numeroFactura'], entityId(sale))}</Link></td><td className="nowrap">{formatDate(firstDefined(sale, ['issuedAt', 'createdAt', 'date', 'fecha']), { includeTime: true })}</td><td>{firstDefined(sale, ['customerName', 'clienteNombre'], 'Consumidor final')}</td><td>{firstDefined(sale, ['cashierName', 'cajeroNombre'], '—')}</td><td className="numeric tabular">{formatMoney(firstDefined(sale, ['subtotal'], '0.00'), firstDefined(sale, ['currency', 'moneda'], currency))}</td><td className="numeric tabular">{formatMoney(firstDefined(sale, ['tax', 'iva'], '0.00'), firstDefined(sale, ['currency', 'moneda'], currency))}</td><td className="numeric tabular"><strong>{formatMoney(firstDefined(sale, ['total'], '0.00'), firstDefined(sale, ['currency', 'moneda'], currency))}</strong></td><td className="actions-cell print-hidden"><Link className="icon-button" to={`/ventas/${entityId(sale)}`} aria-label="Abrir comprobante"><Eye size={17} /></Link></td></tr>)}
            </tbody></table></TableWrap>
            <div className="print-hidden"><Pagination page={query.page} pageSize={query.pageSize} total={state.meta?.total || 0} onPageChange={page} onPageSizeChange={pageSize} /></div>
          </>}
        </>}
      </section>
    </>
  );
}
