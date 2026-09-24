import { useState } from 'react';
import { Eye, EyeOff, LogIn } from 'lucide-react';
import { Link, useLocation, useNavigate } from 'react-router';
import { ApiError, errorMessage } from '../api/client.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { PublicLayout } from '../components/PublicLayout.jsx';
import { InlineAlert } from '../components/Ui.jsx';

export default function LoginPage() {
  const { login, terminationReason, clearTerminationReason } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [values, setValues] = useState({ username: '', password: '' });
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const update = (event) => {
    clearTerminationReason();
    setValues((current) => ({ ...current, [event.target.name]: event.target.value }));
  };

  const submit = async (event) => {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const session = await login(values);
      const requested = location.state?.from?.pathname;
      navigate(session.forcePasswordChange ? '/perfil/seguridad' : (requested || '/inicio'), { replace: true });
    } catch (nextError) {
      setError(nextError);
    } finally {
      setBusy(false);
    }
  };

  return (
    <PublicLayout
      title="Acceder"
      description="Ingresa con tu cuenta de trabajo."
      footer={<p>¿Olvidaste tu contraseña? <Link to="/recuperar">Recuperar acceso</Link></p>}
    >
      {location.state?.passwordChanged && <InlineAlert variant="success" title="Contraseña actualizada">Inicia sesión de nuevo con tu nueva contraseña.</InlineAlert>}
      {terminationReason && <InlineAlert variant="warning" title="Sesión terminada">{terminationReason}</InlineAlert>}
      {error && (
        <InlineAlert variant={error instanceof ApiError && error.status === 429 ? 'warning' : 'error'} title="No se pudo iniciar sesión">
          {errorMessage(error)}
        </InlineAlert>
      )}
      <form className="form-stack" onSubmit={submit} noValidate>
        <div className="field">
          <label htmlFor="username">Usuario</label>
          <input
            id="username"
            name="username"
            type="text"
            autoComplete="username"
            required
            maxLength="100"
            value={values.username}
            onChange={update}
            disabled={busy}
          />
        </div>
        <div className="field">
          <label htmlFor="password">Contraseña</label>
          <div className="password-input">
            <input
              id="password"
              name="password"
              type={showPassword ? 'text' : 'password'}
              autoComplete="current-password"
              required
              maxLength="128"
              value={values.password}
              onChange={update}
              disabled={busy}
            />
            <button type="button" className="icon-button" onClick={() => setShowPassword((value) => !value)} aria-label={showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña'}>
              {showPassword ? <EyeOff aria-hidden="true" /> : <Eye aria-hidden="true" />}
            </button>
          </div>
        </div>
        <button type="submit" className="button button--primary button--block" disabled={busy || !values.username || !values.password}>
          <LogIn size={18} aria-hidden="true" /> {busy ? 'Accediendo…' : 'Acceder'}
        </button>
      </form>
    </PublicLayout>
  );
}
