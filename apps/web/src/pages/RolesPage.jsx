import { useCallback, useEffect, useMemo, useState } from 'react';
import { Pencil, Plus, Search, ShieldCheck } from 'lucide-react';
import { rolesApi } from '../api/endpoints.js';
import { errorMessage } from '../api/client.js';
import { Modal } from '../components/Modal.jsx';
import { EmptyState, ErrorState, InlineAlert, PageHeader, PageLoader, Pagination, StatusBadge, TableWrap } from '../components/Ui.jsx';
import { embeddedList, entityId, firstDefined, normalizeList } from '../utils/format.js';

const NEW_ROLE = { name: '', description: '', permissions: [], active: true };

export default function RolesPage() {
  const [filters, setFilters] = useState({ search: '', page: 1, pageSize: 25, sort: 'name', direction: 'asc' });
  const [query, setQuery] = useState(filters);
  const [state, setState] = useState({ status: 'loading', items: [], total: 0, error: null });
  const [permissionsState, setPermissionsState] = useState({ status: 'loading', items: [], error: null });
  const [editor, setEditor] = useState(null);

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await rolesApi.list(query, signal);
      const items = normalizeList(response.data);
      setState({ status: 'ready', items, total: response.meta?.total ?? items.length, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState((current) => ({ ...current, status: 'error', error }));
    }
  }, [query]);
  useEffect(() => { const controller = new AbortController(); load(controller.signal); return () => controller.abort(); }, [load]);
  useEffect(() => {
    const controller = new AbortController();
    rolesApi.permissions(controller.signal)
      .then((response) => setPermissionsState({ status: 'ready', items: normalizeList(response.data), error: null }))
      .catch((error) => { if (error?.name !== 'AbortError') setPermissionsState({ status: 'error', items: [], error }); });
    return () => controller.abort();
  }, []);

  const submitSearch = (event) => { event.preventDefault(); const next = { ...filters, page: 1 }; setFilters(next); setQuery(next); };
  const page = (value) => { const next = { ...query, page: value }; setFilters(next); setQuery(next); };
  const pageSize = (value) => { const next = { ...query, page: 1, pageSize: value }; setFilters(next); setQuery(next); };
  const reload = () => setQuery((current) => ({ ...current }));

  return (
    <>
      <PageHeader title="Roles y permisos" description="Los permisos son efectivos desde la siguiente operación protegida. El rol administrador conserva controles mínimos de seguridad." actions={<button type="button" className="button button--primary" onClick={() => setEditor(NEW_ROLE)} disabled={permissionsState.status !== 'ready'}><Plus size={18} /> Nuevo rol</button>} />
      {permissionsState.status === 'error' && <InlineAlert variant="error" title="No se cargaron los permisos">{errorMessage(permissionsState.error)}</InlineAlert>}
      <section className="panel">
        <form className="filter-bar" onSubmit={submitSearch} role="search"><div className="field field--grow"><label htmlFor="role-search">Buscar rol</label><div className="input-with-icon"><Search size={17} /><input id="role-search" value={filters.search} onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} maxLength="160" placeholder="Nombre o descripción" /></div></div><button type="submit" className="button button--secondary"><Search size={17} /> Buscar</button></form>
        {state.status === 'loading' && <PageLoader label="Cargando roles…" />}
        {state.status === 'error' && <ErrorState error={state.error} onRetry={reload} />}
        {state.status === 'ready' && !state.items.length && <EmptyState search={Boolean(query.search)}>{query.search ? 'Prueba con otro término.' : 'Aún no hay roles disponibles.'}</EmptyState>}
        {state.status === 'ready' && state.items.length > 0 && <>
          <TableWrap label="Listado de roles"><table><thead><tr><th>Rol</th><th>Descripción</th><th>Permisos</th><th>Estado</th><th className="actions-cell">Acciones</th></tr></thead><tbody>
            {state.items.map((role) => { const permissions = embeddedList(role.permissions); return <tr key={entityId(role)}><td><div className="cell-stack"><strong>{role.name}</strong>{role.administrator && <small><ShieldCheck size={14} /> Rol protegido</small>}</div></td><td>{role.description || 'Sin descripción'}</td><td><div className="chip-list chip-list--limited">{permissions.length ? permissions.map((permission) => <span className="chip chip--accent" key={permission.code}>{permission.code}</span>) : <span className="muted">Sin permisos</span>}</div></td><td><StatusBadge value={role.active === false ? 'Inactivo' : 'Activo'} /></td><td className="actions-cell"><button type="button" className="icon-button" onClick={() => setEditor(role)} aria-label={`Editar rol ${role.name}`}><Pencil size={17} /></button></td></tr>; })}
          </tbody></table></TableWrap>
          <Pagination page={query.page} pageSize={query.pageSize} total={state.total} onPageChange={page} onPageSizeChange={pageSize} />
        </>}
      </section>
      <RoleEditor role={editor} permissions={permissionsState.items} onClose={() => setEditor(null)} onSaved={() => { setEditor(null); reload(); }} />
    </>
  );
}

function RoleEditor({ role, permissions, onClose, onSaved }) {
  const isNew = role === NEW_ROLE;
  const initial = useMemo(() => role ? ({
    name: role.name || '',
    description: role.description || '',
    active: role.active !== false,
    permissions: embeddedList(role.permissions).map((permission) => permission.code),
  }) : NEW_ROLE, [role]);
  const [values, setValues] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [confirmDeactivate, setConfirmDeactivate] = useState(false);
  useEffect(() => { setValues(initial); setError(null); setConfirmDeactivate(false); }, [initial]);

  const groups = useMemo(() => permissions.reduce((result, permission) => {
    const module = firstDefined(permission, ['module', 'modulo'], 'General');
    result[module] = [...(result[module] || []), permission];
    return result;
  }, {}), [permissions]);
  const update = (event) => setValues((current) => ({ ...current, [event.target.name]: event.target.type === 'checkbox' ? event.target.checked : event.target.value }));
  const togglePermission = (code) => setValues((current) => ({ ...current, permissions: current.permissions.includes(code) ? current.permissions.filter((item) => item !== code) : [...current.permissions, code] }));
  const persist = async () => {
    setBusy(true); setError(null); setConfirmDeactivate(false);
    try {
      const payload = { name: values.name, description: values.description, permissions: values.permissions };
      if (isNew) await rolesApi.create(payload);
      else await rolesApi.update(entityId(role), { ...payload, active: values.active, version: role.version });
      onSaved();
    } catch (nextError) { setError(nextError); setBusy(false); }
  };
  const submit = (event) => {
    event.preventDefault();
    if (!isNew && role.active !== false && !values.active && !confirmDeactivate) { setConfirmDeactivate(true); return; }
    void persist();
  };

  return (
    <Modal open={Boolean(role)} title={isNew ? 'Nuevo rol' : `Editar ${role?.name}`} description="Selecciona únicamente los permisos necesarios para las responsabilidades del rol." onClose={onClose} size="large" footer={<><button type="button" className="button button--secondary" onClick={onClose} disabled={busy}>Cancelar</button><button type="submit" form="role-form" className="button button--primary" disabled={busy}>{busy ? 'Guardando…' : 'Guardar rol'}</button></>}>
      {error && <InlineAlert variant={error.status === 409 ? 'warning' : 'error'} title={error.status === 409 ? 'Rol protegido o edición concurrente' : 'No se pudo guardar'}>{errorMessage(error)}</InlineAlert>}
      {role?.administrator && <InlineAlert variant="info" title="Rol administrador protegido">No puede desactivarse y debe conservar `USUARIOS_GESTIONAR` y `ROLES_GESTIONAR`.</InlineAlert>}
      {confirmDeactivate && <InlineAlert variant="warning" title="Confirma la desactivación">Las cuentas asignadas perderán los permisos de este rol en su siguiente operación. <div className="alert-actions"><button type="button" className="button button--secondary button--small" onClick={() => setConfirmDeactivate(false)}>Cancelar</button><button type="button" className="button button--danger button--small" onClick={persist}>Desactivar rol</button></div></InlineAlert>}
      <form id="role-form" className="form-stack" onSubmit={submit}>
        <div className="form-grid"><div className="field"><label htmlFor="role-name">Nombre</label><input id="role-name" name="name" value={values.name} onChange={update} minLength="3" maxLength="60" required disabled={busy} /></div>{role && !isNew && <label className="check-field"><input type="checkbox" name="active" checked={values.active} onChange={update} disabled={busy || role.administrator} /> Rol activo</label>}<div className="field field--span"><label htmlFor="role-description">Descripción</label><textarea id="role-description" name="description" value={values.description} onChange={update} maxLength="200" rows="3" disabled={busy} /></div></div>
        <fieldset className="permission-fieldset" disabled={busy}><legend>Permisos</legend><div className="permission-groups">{Object.entries(groups).map(([module, items]) => <section key={module}><h3>{module}</h3>{items.map((permission) => <label className="permission-option" aria-label={`Seleccionar permiso ${permission.name || permission.code}`} key={permission.code}><input type="checkbox" checked={values.permissions.includes(permission.code)} onChange={() => togglePermission(permission.code)} disabled={role?.administrator && ['USUARIOS_GESTIONAR', 'ROLES_GESTIONAR'].includes(permission.code)} /><span><strong>{permission.name || permission.code}</strong><small>{permission.code}</small></span></label>)}</section>)}</div></fieldset>
      </form>
    </Modal>
  );
}
