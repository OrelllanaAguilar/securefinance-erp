import { AlertCircle, CheckCircle2, Inbox, LoaderCircle, SearchX, TriangleAlert } from 'lucide-react';
import { errorMessage } from '../api/client.js';

export function Spinner({ label = 'Cargando' }) {
  return <LoaderCircle className="spinner" aria-label={label} role="status" />;
}

export function PageLoader({ label = 'Cargando información…' }) {
  return (
    <div className="page-state" role="status" aria-live="polite">
      <Spinner />
      <p>{label}</p>
    </div>
  );
}

export function InlineAlert({ variant = 'info', title, children, onRetry, className = '' }) {
  const icons = { success: CheckCircle2, error: AlertCircle, warning: TriangleAlert, info: AlertCircle };
  const Icon = icons[variant] || AlertCircle;
  return (
    <div className={`alert alert--${variant} ${className}`} role={variant === 'error' ? 'alert' : 'status'}>
      <Icon aria-hidden="true" size={19} />
      <div>
        {title && <strong>{title}</strong>}
        <div>{children}</div>
        {onRetry && <button type="button" className="link-button" onClick={onRetry}>Reintentar</button>}
      </div>
    </div>
  );
}

export function ErrorState({ error, onRetry, title = 'No se pudo cargar la información' }) {
  return (
    <div className="page-state page-state--error" role="alert">
      <AlertCircle aria-hidden="true" size={36} />
      <h2>{title}</h2>
      <p>{errorMessage(error)}</p>
      {onRetry && <button type="button" className="button button--secondary" onClick={onRetry}>Reintentar</button>}
    </div>
  );
}

export function EmptyState({ search = false, title, children }) {
  const Icon = search ? SearchX : Inbox;
  return (
    <div className="empty-state">
      <Icon aria-hidden="true" size={32} />
      <h2>{title || (search ? 'Sin coincidencias' : 'Aún no hay registros')}</h2>
      {children && <p>{children}</p>}
    </div>
  );
}

export function PageHeader({ title, description, actions, eyebrow }) {
  return (
    <header className="page-header">
      <div>
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        <h1>{title}</h1>
        {description && <p className="page-description">{description}</p>}
      </div>
      {actions && <div className="page-actions">{actions}</div>}
    </header>
  );
}

export function StatusBadge({ value }) {
  const normalized = String(value || '').toLowerCase();
  let variant = 'neutral';
  if (['activo', 'activa', 'confirmada', 'éxito', 'aprobado', 'completado'].some((word) => normalized.includes(word))) variant = 'success';
  if (['inactivo', 'inactiva', 'rechazada', 'error', 'revocado', 'bloqueado'].some((word) => normalized.includes(word))) variant = 'danger';
  if (['pendiente', 'desconocido', 'advertencia', 'cambio'].some((word) => normalized.includes(word))) variant = 'warning';
  return <span className={`badge badge--${variant}`}>{value || 'Sin estado'}</span>;
}

export function FieldError({ id, error }) {
  if (!error) return null;
  return <span id={id} className="field-error">{Array.isArray(error) ? error.join(', ') : error}</span>;
}

export function TableWrap({ children, label }) {
  // A scrollable region must be keyboard-focusable even though `region` is not an
  // interactive ARIA role. This is the WCAG pattern for horizontally wide tables.
  // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
  return <div className="table-wrap" role="region" aria-label={label} tabIndex="0">{children}</div>;
}

export function Pagination({ page, pageSize, total, onPageChange, onPageSizeChange }) {
  const pages = Math.max(1, Math.ceil((total || 0) / pageSize));
  return (
    <nav className="pagination" aria-label="Paginación">
      <div className="pagination__size">
        <label htmlFor="page-size">Filas</label>
        <select id="page-size" value={pageSize} onChange={(event) => onPageSizeChange(Number(event.target.value))}>
          {[10, 25, 50].map((size) => <option key={size} value={size}>{size}</option>)}
        </select>
      </div>
      <span>Página {page} de {pages} · {total || 0} registros</span>
      <div className="button-group">
        <button type="button" className="button button--secondary button--small" disabled={page <= 1} onClick={() => onPageChange(page - 1)}>Anterior</button>
        <button type="button" className="button button--secondary button--small" disabled={page >= pages} onClick={() => onPageChange(page + 1)}>Siguiente</button>
      </div>
    </nav>
  );
}

export function RequiredMark() {
  return <span aria-hidden="true" className="required-mark">*</span>;
}
