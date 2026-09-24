import { useState } from 'react';
import { ArrowLeft, Send } from 'lucide-react';
import { Link } from 'react-router';
import { authApi } from '../api/endpoints.js';
import { errorMessage } from '../api/client.js';
import { PublicLayout } from '../components/PublicLayout.jsx';
import { InlineAlert } from '../components/Ui.jsx';

export default function RecoveryPage() {
  const [identifier, setIdentifier] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState(null);

  const submit = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await authApi.recover({ identity: identifier });
      setSent(true);
    } catch (nextError) {
      setError(nextError);
    } finally {
      setBusy(false);
    }
  };

  return (
    <PublicLayout
      title="Recuperar acceso"
      description="Te indicaremos cómo restablecer tu contraseña si la cuenta existe."
      footer={<Link className="back-link" to="/acceso"><ArrowLeft size={16} /> Volver al acceso</Link>}
    >
      {sent ? (
        <InlineAlert variant="success" title="Solicitud recibida">
          Si la cuenta existe, se generaron instrucciones válidas durante 15 minutos. Revisa el canal privado configurado por el administrador.
        </InlineAlert>
      ) : (
        <form className="form-stack" onSubmit={submit}>
          {error && <InlineAlert variant="error">{errorMessage(error)}</InlineAlert>}
          <div className="field">
            <label htmlFor="identifier">Usuario o correo</label>
            <input id="identifier" value={identifier} onChange={(event) => setIdentifier(event.target.value)} required maxLength="254" autoComplete="username" />
          </div>
          <button className="button button--primary button--block" type="submit" disabled={busy || !identifier}>
            <Send size={18} aria-hidden="true" /> {busy ? 'Enviando…' : 'Solicitar recuperación'}
          </button>
        </form>
      )}
    </PublicLayout>
  );
}
