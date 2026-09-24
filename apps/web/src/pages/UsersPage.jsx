import { useCallback, useEffect, useMemo, useState } from 'react';
import { KeyRound, Pencil, Search, UserPlus } from 'lucide-react';
import { rolesApi, usersApi } from '../api/endpoints.js';
import { errorMessage } from '../api/client.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { ConfirmDialog, Modal } from '../components/Modal.jsx';
import { EmptyState, ErrorState, InlineAlert, PageHeader, PageLoader, Pagination, StatusBadge, TableWrap } from '../components/Ui.jsx';
import { embeddedList, entityId, formatDate, normalizeList } from '../utils/format.js';
import { hasPermission, PERMISSIONS } from '../utils/permissions.js';

const NEW_USER = { username: '', displayName: '', email: '', roleIds: [] };

export default function UsersPage() {
  const { user: currentUser } = useAuth();
  const canManageRoles = hasPermission(currentUser, PERMISSIONS.ROLES);
  const [filters, setFilters] = useState({ search: '', page: 1, pageSize: 25, sort: 'name', direction: 'asc' });
  const [query, setQuery] = useState(filters);
  const [state, setState] = useState({ status: 'loading', items: [], total: 0, error: null });
  const [rolesState, setRolesState] = useState({ status: canManageRoles ? 'loading' : 'unavailable', items: [], error: null });
  const [editor, setEditor] = useState(null);
  const [resetTarget, setResetTarget] = useState(null);
  const [resetBusy, setResetBusy] = useState(false);
  const [actionError, setActionError] = useState(null);
  const [credential, setCredential] = useState(null);

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await usersApi.list(query, signal);
      const items = normalizeList(response.data);
      setState({ status: 'ready', items, total: response.meta?.total ?? items.length, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState((current) => ({ ...current, status: 'error', error }));
    }
  }, [query]);

  useEffect(() => { const controller = new AbortController(); load(controller.signal); return () => controller.abort(); }, [load]);
  useEffect(() => {
    if (!canManageRoles) return undefined;
    const controller = new AbortController();
    rolesApi.list({ page: 1, pageSize: 50, search: '', sort: 'name', direction: 'asc' }, controller.signal)
      .then((response) => setRolesState({ status: 'ready', items: normalizeList(response.data).filter((role) => role.active !== false), error: null }))
      .catch((error) => { if (error?.name !== 'AbortError') setRolesState({ status: 'error', items: [], error }); });
    return () => controller.abort();
  }, [canManageRoles]);

  const submitSearch = (event) => { event.preventDefault(); const next = { ...filters, page: 1 }; setFilters(next); setQuery(next); };
  const page = (value) => { const next = { ...query, page: value }; setFilters(next); setQuery(next); };
  const pageSize = (value) => { const next = { ...query, page: 1, pageSize: value }; setFilters(next); setQuery(next); };
  const reload = () => setQuery((current) => ({ ...current }));

  const resetPassword = async () => {
    setResetBusy(true); setActionError(null);
    try {
      const response = await usersApi.resetPassword(entityId(resetTarget));
      setCredential({ username: resetTarget.username, password: response.data?.temporaryPassword, message: response.data?.message });
      setResetTarget(null);
      reload();
    } catch (error) { setActionError(error); setResetTarget(null); }
    finally { setResetBusy(false); }
  };

  return (
    <>
      <PageHeader title="Usuarios" description="Gestiona cuentas, roles y estado. Los cambios de acceso se aplican en la siguiente operación protegida." actions={<button type="button" className="button button--primary" onClick={() => setEditor(NEW_USER)}><UserPlus size={18} /> Nuevo usuario</button>} />
      {actionError && <InlineAlert variant={actionError.status === 409 ? 'warning' : 'error'} title={actionError.status === 409 ? 'Acción protegida' : 'No se pudo completar'}>{errorMessage(actionError)}</InlineAlert>}
      {!canManageRoles && <InlineAlert variant="info" title="Gestión de roles no disponible">Puedes administrar los datos y el estado de las cuentas, pero tu sesión no permite cambiar asignaciones de rol.</InlineAlert>}
      {rolesState.status === 'error' && <InlineAlert variant="warning" title="No se cargaron los roles">Los datos de usuario siguen disponibles. {errorMessage(rolesState.error)}</InlineAlert>}
      <section className="panel">
        <form className="filter-bar" onSubmit={submitSearch} role="search"><div className="field field--grow"><label htmlFor="user-search">Buscar usuario</label><div className="input-with-icon"><Search size={17} /><input id="user-search" value={filters.search} onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} maxLength="160" placeholder="Usuario, nombre o correo" /></div></div><button type="submit" className="button button--secondary"><Search size={17} /> Buscar</button></form>
        {state.status === 'loading' && <PageLoader label="Cargando usuarios…" />}
        {state.status === 'error' && <ErrorState error={state.error} onRetry={reload} />}
        {state.status === 'ready' && !state.items.length && <EmptyState search={Boolean(query.search)}>{query.search ? 'Prueba con otro término.' : 'Aún no hay usuarios disponibles.'}</EmptyState>}
        {state.status === 'ready' && state.items.length > 0 && <>
          <TableWrap label="Listado de usuarios"><table><thead><tr><th>Usuario</th><th>Nombre</th><th>Roles</th><th>Estado</th><th>Última actualización</th><th className="actions-cell">Acciones</th></tr></thead><tbody>
            {state.items.map((account) => { const roles = embeddedList(account.roles); const isCurrentUser = String(entityId(account)) === String(entityId(currentUser)); return <tr key={entityId(account)}><td><strong>{account.username}</strong><small className="block muted">{account.email || 'Sin correo'}</small></td><td>{account.displayName}</td><td><div className="chip-list">{roles.length ? roles.map((role) => <span className="chip" key={role.id || role.name}>{role.name}</span>) : <span className="muted">Sin roles</span>}</div></td><td><div className="cell-stack"><StatusBadge value={account.active === false ? 'Inactivo' : 'Activo'} />{account.mustChangePassword && <small>Cambio de clave pendiente</small>}</div></td><td className="nowrap">{formatDate(account.updatedAt, { includeTime: true })}</td><td className="actions-cell"><div className="row-actions"><button type="button" className="icon-button" onClick={() => setEditor(account)} aria-label={`Editar ${account.username}`}><Pencil size={17} /></button>{!isCurrentUser && <button type="button" className="icon-button" onClick={() => setResetTarget(account)} aria-label={`Generar contraseña temporal para ${account.username}`}><KeyRound size={17} /></button>}</div></td></tr>; })}
          </tbody></table></TableWrap>
          <Pagination page={query.page} pageSize={query.pageSize} total={state.total} onPageChange={page} onPageSizeChange={pageSize} />
        </>}
      </section>
      <UserEditor user={editor} rolesState={rolesState} canManageRoles={canManageRoles} onClose={() => setEditor(null)} onSaved={(result) => { setEditor(null); if (result?.temporaryPassword) setCredential({ username: result.user?.username, password: result.temporaryPassword, message: result.message }); reload(); }} />
      <ConfirmDialog open={Boolean(resetTarget)} title="Generar contraseña temporal" confirmLabel="Generar y revocar sesiones" danger busy={resetBusy} onClose={() => setResetTarget(null)} onConfirm={resetPassword}>Se revocarán las sesiones y tokens anteriores de {resetTarget?.username}. La credencial temporal se mostrará una sola vez.</ConfirmDialog>
      <CredentialDialog credential={credential} onClose={() => setCredential(null)} />
    </>
  );
}

function UserEditor({ user, rolesState, canManageRoles, onClose, onSaved }) {
  const isNew = user === NEW_USER;
  const initial = useMemo(() => {
    if (!user) return NEW_USER;
    const assigned = embeddedList(user.roles).map((role) => Number(role.id));
    return { username: user.username || '', displayName: user.displayName || '', email: user.email || '', active: user.active !== false, roleIds: assigned };
  }, [user]);
  const [values, setValues] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [confirmDeactivate, setConfirmDeactivate] = useState(false);
  useEffect(() => { setValues(initial); setError(null); setConfirmDeactivate(false); }, [initial]);

  const update = (event) => setValues((current) => ({ ...current, [event.target.name]: event.target.type === 'checkbox' ? event.target.checked : event.target.value }));
  const toggleRole = (id) => setValues((current) => ({ ...current, roleIds: current.roleIds.includes(id) ? current.roleIds.filter((roleId) => roleId !== id) : [...current.roleIds, id] }));
  const persist = async () => {
    setBusy(true); setError(null); setConfirmDeactivate(false);
    try {
      if (isNew) {
        const response = await usersApi.create({ username: values.username, displayName: values.displayName, email: values.email, roleIds: canManageRoles ? values.roleIds : [] });
        onSaved(response.data);
      } else {
        const payload = { version: user.version };
        if (values.displayName !== initial.displayName) payload.displayName = values.displayName;
        if (values.email !== initial.email) payload.email = values.email;
        if (values.active !== initial.active) payload.active = values.active;
        const initialRoles = [...initial.roleIds].sort((left, right) => left - right);
        const selectedRoles = [...values.roleIds].sort((left, right) => left - right);
        if (canManageRoles && JSON.stringify(selectedRoles) !== JSON.stringify(initialRoles)) payload.roleIds = values.roleIds;
        if (Object.keys(payload).length === 1) { onSaved(); return; }
        await usersApi.update(entityId(user), payload);
        onSaved();
      }
    } catch (nextError) { setError(nextError); setBusy(false); }
  };
  const submit = (event) => {
    event.preventDefault();
    if (!isNew && user.active !== false && !values.active && !confirmDeactivate) { setConfirmDeactivate(true); return; }
    void persist();
  };

  return (
    <Modal open={Boolean(user)} title={isNew ? 'Nuevo usuario' : `Editar ${user?.username}`} description={isNew ? 'Se generará una credencial temporal privada y se exigirá cambiarla en el primer acceso.' : 'Desactivar o cambiar roles revoca el acceso efectivo en la siguiente operación.'} onClose={onClose} size="large" footer={<><button type="button" className="button button--secondary" onClick={onClose} disabled={busy}>Cancelar</button><button type="submit" form="user-form" className="button button--primary" disabled={busy}>{busy ? 'Guardando…' : 'Guardar usuario'}</button></>}>
      {error && <InlineAlert variant={error.status === 409 ? 'warning' : 'error'} title={error.status === 409 ? 'Cambio en conflicto o cuenta protegida' : 'No se pudo guardar'}>{errorMessage(error)}</InlineAlert>}
      {confirmDeactivate && <InlineAlert variant="warning" title="Confirma la desactivación">Se cerrará el acceso de esta cuenta. <div className="alert-actions"><button type="button" className="button button--secondary button--small" onClick={() => setConfirmDeactivate(false)}>Cancelar</button><button type="button" className="button button--danger button--small" onClick={persist}>Desactivar cuenta</button></div></InlineAlert>}
      <form id="user-form" className="form-grid" onSubmit={submit}>
        <div className="field"><label htmlFor="user-username">Usuario</label><input id="user-username" name="username" value={values.username} onChange={update} minLength="3" maxLength="50" pattern="[A-Za-z0-9._-]+" required disabled={busy || !isNew} /></div>
        <div className="field"><label htmlFor="user-email">Correo de recuperación</label><input id="user-email" name="email" type="email" value={values.email} onChange={update} maxLength="254" disabled={busy} /></div>
        <div className="field field--span"><label htmlFor="user-display-name">Nombre visible</label><input id="user-display-name" name="displayName" value={values.displayName} onChange={update} minLength="2" maxLength="120" required disabled={busy} /></div>
        {!isNew && <label className="check-field field--span"><input type="checkbox" name="active" checked={values.active} onChange={update} disabled={busy} /> Cuenta activa</label>}
        <fieldset className="field field--span permission-fieldset" disabled={busy || !canManageRoles || rolesState.status !== 'ready'}><legend>Roles</legend>{rolesState.status === 'ready' ? <div className="check-grid">{rolesState.items.map((role) => <label className="check-field" key={entityId(role)}><input type="checkbox" checked={values.roleIds.includes(Number(entityId(role)))} onChange={() => toggleRole(Number(entityId(role)))} /> {role.name}</label>)}</div> : <p className="muted">No se pueden modificar los roles en esta sesión.</p>}</fieldset>
      </form>
    </Modal>
  );
}

function CredentialDialog({ credential, onClose }) {
  return (
    <Modal open={Boolean(credential)} title="Credencial temporal" description="Cópiala ahora y entrégala únicamente por un canal privado. No volverá a mostrarse." onClose={onClose} size="small" footer={<button type="button" className="button button--primary" onClick={onClose}>Ya la guardé</button>}>
      <InlineAlert variant="warning" title="Uso único">La cuenta deberá cambiar esta contraseña al iniciar sesión.</InlineAlert>
      <dl className="credential-box"><div><dt>Usuario</dt><dd>{credential?.username || '—'}</dd></div><div><dt>Contraseña temporal</dt><dd><code>{credential?.password || 'No disponible'}</code></dd></div></dl>
      {credential?.message && <p className="muted">{credential.message}</p>}
    </Modal>
  );
}
