import { useCallback, useEffect, useState } from 'react';
import { Search } from 'lucide-react';
import { auditApi } from '../api/endpoints.js';
import { EmptyState, ErrorState, PageHeader, PageLoader, Pagination, TableWrap } from '../components/Ui.jsx';
import { firstDefined, formatDate, normalizeList } from '../utils/format.js';

const CATEGORIES = [
  { id: 'access', label: 'Accesos' },
  { id: 'dml', label: 'Cambios DML' },
  { id: 'ddl', label: 'Esquema DDL' },
];

const COLUMNS = {
  access: [
    ['date', 'Fecha', (row) => formatDate(firstDefined(row, ['date', 'createdAt', 'fechaUtc', 'fecha']), { includeTime: true })],
    ['actor', 'Usuario', (row) => firstDefined(row, ['username', 'actor', 'usuario'], 'Desconocido')],
    ['operation', 'Resultado', (row) => firstDefined(row, ['result', 'operation', 'resultado', 'evento'])],
    ['ip', 'IP observada', (row) => firstDefined(row, ['ipAddress', 'ip', 'direccionIP'], '—')],
    ['correlation', 'Correlación', (row) => firstDefined(row, ['correlationId'], '—')],
  ],
  dml: [
    ['date', 'Fecha', (row) => formatDate(firstDefined(row, ['date', 'createdAt', 'fechaUtc', 'fecha']), { includeTime: true })],
    ['actor', 'Usuario de aplicación', (row) => firstDefined(row, ['applicationUser', 'username', 'actor', 'usuarioAplicacion'], '—')],
    ['operation', 'Operación', (row) => firstDefined(row, ['operation', 'accion', 'operacion'])],
    ['object', 'Objeto', (row) => firstDefined(row, ['objectName', 'tableName', 'objeto', 'tabla'])],
    ['rows', 'Filas', (row) => firstDefined(row, ['rowCount', 'affectedRows', 'filas'], '—')],
    ['correlation', 'Correlación', (row) => firstDefined(row, ['correlationId'], '—')],
  ],
  ddl: [
    ['date', 'Fecha', (row) => formatDate(firstDefined(row, ['date', 'createdAt', 'fechaUtc', 'fecha']), { includeTime: true })],
    ['actor', 'Principal SQL', (row) => firstDefined(row, ['sqlPrincipal', 'loginName', 'principalSql'], '—')],
    ['operation', 'Evento', (row) => firstDefined(row, ['operation', 'eventType', 'evento'])],
    ['object', 'Objeto', (row) => firstDefined(row, ['objectName', 'objeto'], '—')],
    ['correlation', 'Correlación', (row) => firstDefined(row, ['correlationId'], '—')],
  ],
};

export default function AuditPage() {
  const [category, setCategory] = useState('access');
  const [filters, setFilters] = useState({ search: '', from: '', to: '', page: 1, pageSize: 25, sort: 'date', direction: 'desc' });
  const [query, setQuery] = useState(filters);
  const [state, setState] = useState({ status: 'loading', items: [], total: 0, error: null });

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await auditApi.list(category, query, signal);
      const items = normalizeList(response.data);
      setState({ status: 'ready', items, total: response.meta?.total ?? items.length, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState((current) => ({ ...current, status: 'error', error }));
    }
  }, [category, query]);
  useEffect(() => { const controller = new AbortController(); load(controller.signal); return () => controller.abort(); }, [load]);

  const selectCategory = (nextCategory) => { setCategory(nextCategory); const next = { ...query, page: 1 }; setFilters(next); setQuery(next); };
  const submit = (event) => { event.preventDefault(); const next = { ...filters, page: 1 }; setFilters(next); setQuery(next); };
  const page = (value) => { const next = { ...query, page: value }; setFilters(next); setQuery(next); };
  const pageSize = (value) => { const next = { ...query, page: 1, pageSize: value }; setFilters(next); setQuery(next); };
  const reload = () => setQuery((current) => ({ ...current }));
  const columns = COLUMNS[category];

  return (
    <>
      <PageHeader title="Auditoría" description="Consulta separadamente accesos, cambios de datos y eventos de esquema. No se muestran secretos ni credenciales." />
      <section className="panel">
        <div className="tabs" role="tablist" aria-label="Tipo de auditoría">{CATEGORIES.map((item) => <button key={item.id} type="button" role="tab" aria-selected={category === item.id} className={category === item.id ? 'active' : undefined} onClick={() => selectCategory(item.id)}>{item.label}</button>)}</div>
        <form className="filter-bar filter-bar--wrap" onSubmit={submit} role="search">
          <div className="field field--grow"><label htmlFor="audit-search">Buscar</label><div className="input-with-icon"><Search size={17} /><input id="audit-search" value={filters.search} maxLength="160" onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} placeholder="Actor, operación u objeto" /></div></div>
          <div className="field"><label htmlFor="audit-from">Desde</label><input id="audit-from" type="date" value={filters.from} onChange={(event) => setFilters((current) => ({ ...current, from: event.target.value }))} /></div>
          <div className="field"><label htmlFor="audit-to">Hasta</label><input id="audit-to" type="date" value={filters.to} onChange={(event) => setFilters((current) => ({ ...current, to: event.target.value }))} /></div>
          <button className="button button--secondary" type="submit"><Search size={17} /> Aplicar</button>
        </form>
        {state.status === 'loading' && <PageLoader label="Consultando bitácora…" />}
        {state.status === 'error' && <ErrorState error={state.error} onRetry={reload} title="No se pudo consultar la auditoría" />}
        {state.status === 'ready' && !state.items.length && <EmptyState search={Boolean(query.search || query.from || query.to)}>No hay eventos que coincidan con la consulta.</EmptyState>}
        {state.status === 'ready' && state.items.length > 0 && <>
          <TableWrap label={`Auditoría: ${CATEGORIES.find((item) => item.id === category)?.label}`}><table><thead><tr>{columns.map(([key, label]) => <th key={key}>{label}</th>)}</tr></thead><tbody>{state.items.map((row, index) => <tr key={firstDefined(row, ['id', 'auditId', 'correlationId'], index)}>{columns.map(([key, , render]) => <td key={key} className={key === 'correlation' ? 'code-cell' : undefined}>{render(row)}</td>)}</tr>)}</tbody></table></TableWrap>
          <Pagination page={query.page} pageSize={query.pageSize} total={state.total} onPageChange={page} onPageSizeChange={pageSize} />
        </>}
      </section>
    </>
  );
}
