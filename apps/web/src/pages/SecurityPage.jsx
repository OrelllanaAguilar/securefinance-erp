import { useMemo, useState } from 'react';
import { KeyRound } from 'lucide-react';
import { useNavigate } from 'react-router';
import { meApi } from '../api/endpoints.js';
import { errorMessage } from '../api/client.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { FieldError, InlineAlert, PageHeader } from '../components/Ui.jsx';

function isStrong(value) {
  return value.length >= 12 && value.length <= 128 && /[A-Z]/.test(value) && /[a-z]/.test(value) && /\d/.test(value) && /[^A-Za-z0-9]/.test(value);
}

export default function SecurityPage() {
  const { forcePasswordChange, logout } = useAuth();
  const navigate = useNavigate();
  const [values, setValues] = useState({ currentPassword: '', newPassword: '', confirmation: '' });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const valid = useMemo(() => values.currentPassword && isStrong(values.newPassword) && values.newPassword === values.confirmation, [values]);

  const update = (event) => setValues((current) => ({ ...current, [event.target.name]: event.target.value }));
  const submit = async (event) => {
    event.preventDefault();
    if (!valid) return;
    setBusy(true);
    setError(null);
    try {
      await meApi.password({ currentPassword: values.currentPassword, newPassword: values.newPassword });
      try {
        await logout();
      } catch {
        // El cambio ya se confirmó y logout siempre limpia la sesión local.
      }
      navigate('/acceso', { replace: true, state: { passwordChanged: true } });
    } catch (nextError) {
      setError(nextError);
      setBusy(false);
    }
  };

  return (
    <>
      <PageHeader title="Seguridad" description="Actualiza tu contraseña. El cambio revoca las demás sesiones y tokens de recuperación." />
      <section className="panel form-panel">
        {forcePasswordChange && <InlineAlert variant="warning" title="Cambio obligatorio">Debes establecer una contraseña nueva antes de utilizar otros módulos.</InlineAlert>}
        {error && <InlineAlert variant="error" title="No se pudo cambiar la contraseña">{errorMessage(error)}</InlineAlert>}
        <form className="form-stack" onSubmit={submit}>
          <div className="field">
            <label htmlFor="currentPassword">Contraseña actual o temporal</label>
            <input id="currentPassword" name="currentPassword" type="password" autoComplete="current-password" required maxLength="128" value={values.currentPassword} onChange={update} disabled={busy} />
          </div>
          <div className="field">
            <label htmlFor="newPassword">Nueva contraseña</label>
            <input id="newPassword" name="newPassword" type="password" autoComplete="new-password" required minLength="12" maxLength="128" value={values.newPassword} onChange={update} disabled={busy} aria-describedby="password-help" />
            <span className="field-help" id="password-help">12–128 caracteres, con mayúscula, minúscula, número y símbolo. No se eliminan espacios.</span>
          </div>
          <div className="field">
            <label htmlFor="confirmation">Confirmar contraseña nueva</label>
            <input id="confirmation" name="confirmation" type="password" autoComplete="new-password" required maxLength="128" value={values.confirmation} onChange={update} disabled={busy} aria-invalid={values.confirmation && values.confirmation !== values.newPassword ? 'true' : undefined} aria-describedby="security-confirm-error" />
            <FieldError id="security-confirm-error" error={values.confirmation && values.confirmation !== values.newPassword ? 'Las contraseñas no coinciden.' : null} />
          </div>
          <div className="form-actions">
            <button type="submit" className="button button--primary" disabled={!valid || busy}><KeyRound size={17} /> {busy ? 'Actualizando…' : 'Cambiar contraseña'}</button>
          </div>
        </form>
      </section>
    </>
  );
}
