import { useCallback, useEffect, useRef, useState } from 'react';
import { KeyRound, ShieldCheck, UserRound } from 'lucide-react';
import { Link } from 'react-router';
import { meApi } from '../api/endpoints.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { ThemeSelector } from '../components/ThemeSelector.jsx';
import { ErrorState, PageHeader, PageLoader } from '../components/Ui.jsx';
import { firstDefined } from '../utils/format.js';
import { permissionSet } from '../utils/permissions.js';

export default function ProfilePage() {
  const { user, updateUser } = useAuth();
  const userRef = useRef(user);
  const [state, setState] = useState({ status: 'loading', data: null, error: null });

  useEffect(() => { userRef.current = user; }, [user]);

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await meApi.get(signal);
      const data = response.data || userRef.current || {};
      setState({ status: 'ready', data, error: null });
      updateUser(data);
    } catch (error) {
      if (error?.name !== 'AbortError') setState({ status: 'error', data: null, error });
    }
  }, [updateUser]);

  useEffect(() => {
    const controller = new AbortController();
    load(controller.signal);
    return () => controller.abort();
  }, [load]);

  return (
    <>
      <PageHeader
        title="Mi perfil"
        description="Consulta tus datos, roles y permisos efectivos."
        actions={<Link to="/perfil/seguridad" className="button button--secondary"><KeyRound size={17} /> Cambiar contraseña</Link>}
      />
      {state.status === 'loading' && <PageLoader />}
      {state.status === 'error' && <ErrorState error={state.error} onRetry={() => load()} />}
      {state.status === 'ready' && <ProfileContent data={state.data} />}
    </>
  );
}

function ProfileContent({ data }) {
  const permissions = [...permissionSet(data)];
  const roles = data.roles || data.rolesAsignados || [];
  return (
    <div className="two-column-grid">
      <section className="panel profile-card">
        <div className="profile-avatar"><UserRound size={28} /></div>
        <div>
          <p className="eyebrow">Cuenta</p>
          <h2>{firstDefined(data, ['displayName', 'name', 'nombreCompleto', 'username'], 'Usuario')}</h2>
          <dl className="details-list">
            <div><dt>Usuario</dt><dd>{firstDefined(data, ['username', 'usuario'], '—')}</dd></div>
            <div><dt>Correo</dt><dd>{firstDefined(data, ['email', 'correo'], '—')}</dd></div>
            <div><dt>Estado</dt><dd>{firstDefined(data, ['status', 'estado'], 'Activo')}</dd></div>
          </dl>
        </div>
      </section>
      <section className="panel">
        <p className="eyebrow">Preferencia</p>
        <h2>Apariencia</h2>
        <p className="section-description">La preferencia de tu cuenta se aplica en este navegador y se guarda en el servidor.</p>
        <ThemeSelector />
      </section>
      <section className="panel panel--span">
        <div className="panel__header"><div><p className="eyebrow">Acceso efectivo</p><h2>Roles y permisos</h2></div><ShieldCheck aria-hidden="true" /></div>
        <div className="role-summary">
          <div><h3>Roles</h3><div className="chip-list">{roles.length ? roles.map((role) => <span className="chip" key={typeof role === 'string' ? role : role.id || role.code}>{typeof role === 'string' ? role : role.name || role.nombre}</span>) : <span className="muted">Sin roles asignados</span>}</div></div>
          <div><h3>Permisos</h3><div className="chip-list">{permissions.length ? permissions.map((permission) => <span className="chip chip--accent" key={permission}>{permission}</span>) : <span className="muted">Solo funciones personales autorizadas</span>}</div></div>
        </div>
      </section>
    </div>
  );
}
