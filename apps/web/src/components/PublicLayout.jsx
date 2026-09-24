import { Link } from 'react-router';
import { ShieldCheck } from 'lucide-react';
import { ThemeSelector } from './ThemeSelector.jsx';

export function PublicLayout({ title, description, children, footer }) {
  return (
    <main className="auth-shell">
      <section className="auth-card" aria-labelledby="auth-title">
        <header className="auth-card__header">
          <Link to="/acceso" className="brand brand--auth" aria-label="SecureFinance ERP">
            <span className="brand__mark">SF</span>
            <span><strong>SecureFinance</strong><small>ERP local</small></span>
          </Link>
          <div className="auth-heading">
            <h1 id="auth-title">{title}</h1>
            {description && <p>{description}</p>}
          </div>
        </header>
        {children}
        {footer && <footer className="auth-card__footer">{footer}</footer>}
        <div className="auth-card__theme"><ThemeSelector /></div>
      </section>
      <p className="auth-security-note"><ShieldCheck size={16} aria-hidden="true" /> Sesión protegida y operaciones auditadas</p>
    </main>
  );
}
