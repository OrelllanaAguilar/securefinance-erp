import { useEffect, useId, useRef } from 'react';
import { X } from 'lucide-react';

const FOCUSABLE = 'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function Modal({ open, title, description, onClose, children, footer, size = 'medium' }) {
  const titleId = useId();
  const descriptionId = useId();
  const panelRef = useRef(null);
  const previousFocusRef = useRef(null);
  const onCloseRef = useRef(onClose);

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    if (!open) return undefined;
    previousFocusRef.current = document.activeElement;
    const panel = panelRef.current;
    const initialFocus = panel?.querySelector(`.modal__body ${FOCUSABLE}`)
      || panel?.querySelector(`.modal__footer ${FOCUSABLE}`)
      || panel?.querySelector(FOCUSABLE);
    (initialFocus || panel)?.focus();
    const onKeyDown = (event) => {
      if (event.key === 'Escape') onCloseRef.current();
      if (event.key !== 'Tab' || !panel) return;
      const items = [...panel.querySelectorAll(FOCUSABLE)];
      if (!items.length) return;
      const first = items[0];
      const last = items.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    document.body.classList.add('modal-open');
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.classList.remove('modal-open');
      previousFocusRef.current?.focus?.();
    };
  }, [open]);

  if (!open) return null;
  return (
    <div className="modal-backdrop">
      <button type="button" className="modal-backdrop__dismiss" tabIndex="-1" aria-label="Cerrar diálogo" onClick={onClose} />
      <section
        ref={panelRef}
        className={`modal modal--${size}`}
        role="dialog"
        tabIndex="-1"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descriptionId : undefined}
      >
        <header className="modal__header">
          <div>
            <h2 id={titleId}>{title}</h2>
            {description && <p id={descriptionId}>{description}</p>}
          </div>
          <button type="button" className="icon-button" onClick={onClose} aria-label="Cerrar diálogo"><X aria-hidden="true" /></button>
        </header>
        <div className="modal__body">{children}</div>
        {footer && <footer className="modal__footer">{footer}</footer>}
      </section>
    </div>
  );
}

export function ConfirmDialog({ open, title, children, confirmLabel = 'Confirmar', danger = false, busy = false, onConfirm, onClose }) {
  return (
    <Modal
      open={open}
      title={title}
      onClose={busy ? () => {} : onClose}
      size="small"
      footer={(
        <>
          <button type="button" className="button button--secondary" disabled={busy} onClick={onClose}>Cancelar</button>
          <button type="button" className={`button ${danger ? 'button--danger' : 'button--primary'}`} disabled={busy} onClick={onConfirm}>
            {busy ? 'Procesando…' : confirmLabel}
          </button>
        </>
      )}
    >
      <p>{children}</p>
    </Modal>
  );
}
