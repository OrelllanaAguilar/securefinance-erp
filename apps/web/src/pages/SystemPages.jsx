import { ArrowLeft, LockKeyhole, MapPinOff } from 'lucide-react';
import { Link } from 'react-router';

export function ForbiddenPage() {
  return (
    <section className="system-page">
      <LockKeyhole size={42} aria-hidden="true" />
      <h1>Acceso no autorizado</h1>
      <p>Tu cuenta no tiene el permiso necesario. Los permisos se validan de nuevo en cada operación.</p>
      <Link className="button button--secondary" to="/inicio"><ArrowLeft size={17} /> Volver al inicio</Link>
    </section>
  );
}

export function NotFoundPage() {
  return (
    <main className="system-page system-page--standalone">
      <MapPinOff size={42} aria-hidden="true" />
      <h1>Página no encontrada</h1>
      <p>La dirección no existe o dejó de estar disponible.</p>
      <Link className="button button--secondary" to="/inicio"><ArrowLeft size={17} /> Ir al inicio</Link>
    </main>
  );
}
