import { useLayoutEffect, useMemo, useState } from 'react';
import { ArrowLeft, KeyRound } from 'lucide-react';
import { Link, useSearchParams } from 'react-router';
import { authApi } from '../api/endpoints.js';
import { errorMessage } from '../api/client.js';
import { PublicLayout } from '../components/PublicLayout.jsx';
import { FieldError, InlineAlert } from '../components/Ui.jsx';

function passwordChecks(value) {
  return [
    ['Entre 12 y 128 caracteres', value.length >= 12 && value.length <= 128],
    ['Al menos una mayúscula y una minúscula', /[A-Z]/.test(value) && /[a-z]/.test(value)],
    ['Al menos un número', /\d/.test(value)],
    ['Al menos un símbolo', /[^A-Za-z0-9]/.test(value)],
  ];
}

export default function ResetPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [tokenInUrl] = useState(() => searchParams.has('token'));
  const [tokenFromLink] = useState(() => Boolean(searchParams.get('token')));
  const [token, setToken] = useState(() => searchParams.get('token') || '');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [busy, setBusy] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState(null);
  const checks = useMemo(() => passwordChecks(password), [password]);
  const valid = token && checks.every(([, passes]) => passes) && password === confirmation;

  useLayoutEffect(() => {
    if (!tokenInUrl || !searchParams.has('token')) return;
    const sanitized = new URLSearchParams(searchParams);
    sanitized.delete('token');
    setSearchParams(sanitized, { replace: true });
  }, [searchParams, setSearchParams, tokenInUrl]);

  const submit = async (event) => {
    event.preventDefault();
    if (!valid) return;
    setBusy(true);
    setError(null);
    try {
      await authApi.reset({ token, newPassword: password });
      setSuccess(true);
      setToken('');
      setPassword('');
      setConfirmation('');
    } catch (nextError) {
      setError(nextError);
    } finally {
      setBusy(false);
    }
  };

  return (
    <PublicLayout
      title="Restablecer contraseña"
      description="El enlace es de un solo uso y vence 15 minutos después de su emisión."
      footer={<Link className="back-link" to="/acceso"><ArrowLeft size={16} /> Volver al acceso</Link>}
    >
      {success ? (
        <InlineAlert variant="success" title="Contraseña actualizada">
          Se revocaron las sesiones anteriores. Ya puedes <Link to="/acceso">iniciar sesión</Link>.
        </InlineAlert>
      ) : (
        <form className="form-stack" onSubmit={submit}>
          {error && <InlineAlert variant="error" title="No se pudo restablecer">{errorMessage(error)}</InlineAlert>}
          {!tokenFromLink && (
            <div className="field">
              <label htmlFor="token">Código de recuperación</label>
              <input id="token" value={token} onChange={(event) => setToken(event.target.value)} required minLength="32" maxLength="256" autoComplete="one-time-code" />
            </div>
          )}
          <div className="field">
            <label htmlFor="new-password">Nueva contraseña</label>
            <input id="new-password" type="password" value={password} onChange={(event) => setPassword(event.target.value)} required minLength="12" maxLength="128" autoComplete="new-password" />
            <ul className="password-rules" aria-label="Requisitos de contraseña">
              {checks.map(([label, passes]) => <li key={label} className={passes ? 'passes' : undefined}>{label}</li>)}
            </ul>
          </div>
          <div className="field">
            <label htmlFor="confirm-password">Confirmar contraseña</label>
            <input id="confirm-password" type="password" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} required maxLength="128" autoComplete="new-password" aria-invalid={confirmation && password !== confirmation ? 'true' : undefined} aria-describedby="confirmation-error" />
            <FieldError id="confirmation-error" error={confirmation && password !== confirmation ? 'Las contraseñas no coinciden.' : null} />
          </div>
          <button type="submit" className="button button--primary button--block" disabled={busy || !valid}>
            <KeyRound size={18} /> {busy ? 'Actualizando…' : 'Restablecer contraseña'}
          </button>
        </form>
      )}
    </PublicLayout>
  );
}
