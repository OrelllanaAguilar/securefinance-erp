import { useCallback, useEffect, useMemo, useState } from 'react';
import { Pencil, Search, UserPlus } from 'lucide-react';
import { customersApi } from '../api/endpoints.js';
import { errorMessage } from '../api/client.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { Modal } from '../components/Modal.jsx';
import { EmptyState, ErrorState, InlineAlert, PageHeader, PageLoader, Pagination, StatusBadge, TableWrap } from '../components/Ui.jsx';
import { entityId, firstDefined, normalizeList } from '../utils/format.js';
import { hasPermission, PERMISSIONS } from '../utils/permissions.js';

const NEW_CUSTOMER = { identifier: '', name: '', email: '', phone: '', active: true };

export default function CustomersPage() {
  const { user } = useAuth();
  const canManage = hasPermission(user, PERMISSIONS.CUSTOMERS);
  const [filters, setFilters] = useState({ search: '', status: 'active', page: 1, pageSize: 25 });
  const [query, setQuery] = useState(filters);
  const [state, setState] = useState({ status: 'loading', items: [], total: 0, error: null });
  const [editor, setEditor] = useState(null);

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await customersApi.list(query, signal);
      const items = normalizeList(response.data);
      setState({ status: 'ready', items, total: response.meta?.total ?? response.data?.total ?? items.length, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState((current) => ({ ...current, status: 'error', error }));
    }
  }, [query]);

  useEffect(() => {
    const controller = new AbortController();
    load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const applyFilters = (event) => {
    event.preventDefault();
    const next = { ...filters, page: 1 };
    setFilters(next); setQuery(next);
  };
  const page = (pageNumber) => { const next = { ...query, page: pageNumber }; setFilters(next); setQuery(next); };
  const pageSize = (size) => { const next = { ...query, page: 1, pageSize: size }; setFilters(next); setQuery(next); };
  const reload = () => setQuery((current) => ({ ...current }));

  return (
    <>
      <PageHeader
        title="Clientes"
        description={canManage ? 'Mantén los datos y el estado de clientes sin alterar facturas históricas.' : 'Busca clientes activos para preparar ventas.'}
        actions={canManage && <button type="button" className="button button--primary" onClick={() => setEditor(NEW_CUSTOMER)}><UserPlus size={18} /> Nuevo cliente</button>}
      />
      <section className="panel">
        <form className="filter-bar" onSubmit={applyFilters} role="search">
          <div className="field field--grow"><label htmlFor="customer-search">Buscar cliente</label><div className="input-with-icon"><Search size={17} /><input id="customer-search" value={filters.search} maxLength="160" onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} placeholder="Nombre o identificación" /></div></div>
          <div className="field"><label htmlFor="customer-status">Estado</label><select id="customer-status" value={filters.status} onChange={(event) => setFilters((current) => ({ ...current, status: event.target.value }))}><option value="active">Activos</option><option value="inactive">Inactivos</option><option value="all">Todos</option></select></div>
          <button type="submit" className="button button--secondary"><Search size={17} /> Buscar</button>
        </form>
        {state.status === 'loading' && <PageLoader label="Cargando clientes…" />}
        {state.status === 'error' && <ErrorState error={state.error} onRetry={reload} />}
        {state.status === 'ready' && !state.items.length && <EmptyState search={Boolean(query.search)}>{query.search ? 'Prueba con otro nombre o identificación.' : 'Aún no hay clientes registrados.'}</EmptyState>}
        {state.status === 'ready' && state.items.length > 0 && <>
          <TableWrap label="Listado de clientes"><table><thead><tr><th>Identificación</th><th>Nombre</th><th>Contacto</th><th>Estado</th>{canManage && <th className="actions-cell">Acciones</th>}</tr></thead><tbody>
            {state.items.map((customer) => <tr key={entityId(customer)}>
              <td className="tabular">{firstDefined(customer, ['identifier', 'taxId', 'identification', 'nit', 'identificacion'], '—')}</td>
              <td><strong>{firstDefined(customer, ['name', 'nombre', 'businessName', 'razonSocial'])}</strong></td>
              <td><div className="cell-stack"><span>{firstDefined(customer, ['email', 'correo'], 'Sin correo')}</span><small>{firstDefined(customer, ['phone', 'telefono'], 'Sin teléfono')}</small></div></td>
              <td><StatusBadge value={(customer.active ?? customer.activo) === false ? 'Inactivo' : 'Activo'} /></td>
              {canManage && <td className="actions-cell"><button type="button" className="icon-button" onClick={() => setEditor(customer)} aria-label={`Editar ${firstDefined(customer, ['name', 'nombre'])}`}><Pencil size={17} /></button></td>}
            </tr>)}
          </tbody></table></TableWrap>
          <Pagination page={query.page} pageSize={query.pageSize} total={state.total} onPageChange={page} onPageSizeChange={pageSize} />
        </>}
      </section>
      <CustomerEditor customer={editor} onClose={() => setEditor(null)} onSaved={() => { setEditor(null); reload(); }} />
    </>
  );
}

function CustomerEditor({ customer, onClose, onSaved }) {
  const isNew = customer === NEW_CUSTOMER;
  const initial = useMemo(() => customer ? ({
    identifier: firstDefined(customer, ['identifier', 'taxId', 'identification', 'nit', 'identificacion']),
    name: firstDefined(customer, ['name', 'nombre', 'businessName', 'razonSocial']),
    email: firstDefined(customer, ['email', 'correo']),
    phone: firstDefined(customer, ['phone', 'telefono']),
    active: (customer.active ?? customer.activo) !== false,
  }) : NEW_CUSTOMER, [customer]);
  const [values, setValues] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  useEffect(() => { setValues(initial); setError(null); }, [initial]);
  const update = (event) => setValues((current) => ({ ...current, [event.target.name]: event.target.type === 'checkbox' ? event.target.checked : event.target.value }));
  const submit = async (event) => {
    event.preventDefault(); setBusy(true); setError(null);
    try {
      if (isNew) {
        const { active: _active, ...payload } = values;
        await customersApi.create(payload);
      } else {
        await customersApi.update(entityId(customer), { ...values, version: customer?.version ?? customer?.rowVersion });
      }
      onSaved();
    } catch (nextError) { setError(nextError); setBusy(false); }
  };
  return (
    <Modal open={Boolean(customer)} title={isNew ? 'Nuevo cliente' : 'Editar cliente'} description="Los cambios del catálogo no modifican comprobantes anteriores." onClose={onClose} footer={<><button type="button" className="button button--secondary" onClick={onClose} disabled={busy}>Cancelar</button><button type="submit" form="customer-form" className="button button--primary" disabled={busy}>{busy ? 'Guardando…' : 'Guardar cliente'}</button></>}>
      {error && <InlineAlert variant={error?.status === 409 ? 'warning' : 'error'} title={error?.status === 409 ? 'Edición concurrente' : 'No se pudo guardar'}>{errorMessage(error)}</InlineAlert>}
      <form id="customer-form" className="form-grid" onSubmit={submit}>
        <div className="field"><label htmlFor="customer-tax-id">Identificación</label><input id="customer-tax-id" name="identifier" value={values.identifier} onChange={update} maxLength="30" required disabled={busy} /></div>
        <div className="field"><label htmlFor="customer-phone">Teléfono</label><input id="customer-phone" name="phone" type="tel" value={values.phone} onChange={update} maxLength="30" disabled={busy} /></div>
        <div className="field field--span"><label htmlFor="customer-name">Nombre o razón social</label><input id="customer-name" name="name" value={values.name} onChange={update} maxLength="120" required disabled={busy} /></div>
        <div className="field field--span"><label htmlFor="customer-email">Correo</label><input id="customer-email" name="email" type="email" value={values.email} onChange={update} maxLength="254" disabled={busy} /></div>
        {!isNew && <label className="check-field field--span"><input type="checkbox" name="active" checked={values.active} onChange={update} disabled={busy} /> Cliente activo</label>}
      </form>
    </Modal>
  );
}
