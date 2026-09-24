import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { Modal } from './Modal.jsx';

describe('Modal', () => {
  it('expone semántica de diálogo y permite cerrar con Escape', () => {
    const onClose = vi.fn();
    render(<Modal open title="Editar registro" description="Descripción" onClose={onClose}><button type="button">Acción</button></Modal>);
    expect(screen.getByRole('dialog', { name: 'Editar registro' })).toHaveAttribute('aria-modal', 'true');
    expect(screen.getByRole('button', { name: 'Acción' })).toHaveFocus();
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
