import { useEffect, useMemo, useRef, useState } from 'react';
import { Check, Minus, Plus, RefreshCw, Search, ShoppingCart, Trash2, UserRound } from 'lucide-react';
import { useBlocker, useNavigate } from 'react-router';
import { customersApi, productsApi, salesApi } from '../api/endpoints.js';
import { errorMessage } from '../api/client.js';
import { ConfirmDialog } from '../components/Modal.jsx';
import { EmptyState, InlineAlert, PageHeader, StatusBadge, TableWrap } from '../components/Ui.jsx';
import { entityId, firstDefined, formatMoney, normalizeList } from '../utils/format.js';
import { classifySaleFailure, saleResultOutcome } from '../utils/sale.js';

const SALE_STATUS = {
  DRAFT: 'Borrador',
  READY: 'Lista para confirmar',
  SENDING: 'Enviando',
  REJECTED: 'Rechazada',
  UNKNOWN: 'Resultado desconocido',
  CONFIRMED: 'Confirmada',
};

function newKey() {
  return crypto.randomUUID();
}

export default function SaleNewPage() {
  const navigate = useNavigate();
  const [customerSearch, setCustomerSearch] = useState('');
  const [customerResults, setCustomerResults] = useState({ status: 'idle', items: [], error: null });
  const [customer, setCustomer] = useState(null);
  const [productSearch, setProductSearch] = useState('');
  const [productResults, setProductResults] = useState({ status: 'idle', items: [], error: null });
  const [cart, setCart] = useState([]);
  const [quote, setQuote] = useState(null);
  const [status, setStatus] = useState(SALE_STATUS.DRAFT);
  const [idempotencyKey, setIdempotencyKey] = useState(newKey);
  const [attempted, setAttempted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [message, setMessage] = useState(null);
  const allowNavigationRef = useRef(false);

  const locked = busy || status === SALE_STATUS.UNKNOWN || status === SALE_STATUS.SENDING || status === SALE_STATUS.CONFIRMED;
  const hasPendingSale = status === SALE_STATUS.UNKNOWN || status === SALE_STATUS.SENDING || Boolean(customer) || cart.length > 0;
  const itemsPayload = useMemo(() => cart.map((line) => ({ productId: entityId(line.product), quantity: line.quantity })), [cart]);
  const blocker = useBlocker(({ currentLocation, nextLocation }) => (
    !allowNavigationRef.current
    && hasPendingSale
    && status !== SALE_STATUS.CONFIRMED
    && currentLocation.pathname !== nextLocation.pathname
  ));

  useEffect(() => {
    const warn = (event) => {
      if (!hasPendingSale || status === SALE_STATUS.CONFIRMED) return;
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [hasPendingSale, status]);

  const invalidateQuote = () => {
    setQuote(null);
    setStatus(SALE_STATUS.DRAFT);
    setMessage(null);
    if (attempted) {
      setIdempotencyKey(newKey());
      setAttempted(false);
    }
  };

  const findCustomers = async (event) => {
    event.preventDefault();
    setCustomerResults({ status: 'loading', items: [], error: null });
    try {
      const response = await customersApi.list({ search: customerSearch, status: 'active', page: 1, pageSize: 10 });
      setCustomerResults({ status: 'ready', items: normalizeList(response.data), error: null });
    } catch (error) { setCustomerResults({ status: 'error', items: [], error }); }
  };
  const selectCustomer = (item) => {
    if (locked) return;
    setCustomer(item); setCustomerResults({ status: 'idle', items: [], error: null }); setCustomerSearch(''); invalidateQuote();
  };
  const findProducts = async (event) => {
    event.preventDefault();
    setProductResults({ status: 'loading', items: [], error: null });
    try {
      const response = await productsApi.list({ search: productSearch, status: 'active', page: 1, pageSize: 10 });
      setProductResults({ status: 'ready', items: normalizeList(response.data), error: null });
    } catch (error) { setProductResults({ status: 'error', items: [], error }); }
  };
  const addProduct = (product) => {
    if (locked) return;
    setCart((current) => {
      const id = entityId(product);
      const found = current.find((line) => entityId(line.product) === id);
      if (found) return current.map((line) => entityId(line.product) === id ? { ...line, quantity: Math.min(9999, line.quantity + 1) } : line);
      if (current.length >= 100) { setMessage({ variant: 'warning', title: 'Límite alcanzado', text: 'Una venta admite hasta 100 productos distintos.' }); return current; }
      return [...current, { product, quantity: 1 }];
    });
    setProductResults({ status: 'idle', items: [], error: null }); setProductSearch(''); invalidateQuote();
  };
  const changeQuantity = (productId, value) => {
    if (locked) return;
    const quantity = Math.max(1, Math.min(9999, Number.parseInt(value || '1', 10)));
    setCart((current) => current.map((line) => entityId(line.product) === productId ? { ...line, quantity } : line));
    invalidateQuote();
  };
  const removeProduct = (productId) => { if (locked) return; setCart((current) => current.filter((line) => entityId(line.product) !== productId)); invalidateQuote(); };

  const requestQuote = async () => {
    if (!customer || !cart.length) return;
    setBusy(true); setMessage(null);
    try {
      const response = await salesApi.quote({ customerId: entityId(customer), lines: itemsPayload });
      setQuote(response.data);
      setStatus(SALE_STATUS.READY);
      setMessage({ variant: 'success', title: 'Cotización actualizada', text: 'Precios, IVA y existencia fueron validados por el servidor.' });
    } catch (error) {
      setQuote(null); setStatus(SALE_STATUS.REJECTED);
      setMessage({ variant: error?.status === 409 ? 'warning' : 'error', title: error?.status === 409 ? 'La venta necesita cambios' : 'No se pudo cotizar', text: errorMessage(error) });
    } finally { setBusy(false); }
  };

  const confirmSale = async () => {
    setConfirmOpen(false); setBusy(true); setStatus(SALE_STATUS.SENDING); setMessage(null); setAttempted(true);
    const payload = {
      customerId: entityId(customer),
      lines: itemsPayload,
      acceptedTotal: String(firstDefined(quote?.totals, ['total'], '')),
      idempotencyKey,
    };
    try {
      const response = await salesApi.create(payload);
      const result = response.data || {};
      const saleId = firstDefined(result, ['id', 'saleId', 'invoiceId', 'facturaId']);
      setStatus(SALE_STATUS.CONFIRMED);
      if (saleId) { allowNavigationRef.current = true; navigate(`/ventas/${saleId}`, { replace: true }); }
      else setMessage({ variant: 'success', title: 'Venta confirmada', text: 'La venta fue registrada. Consulta Mis ventas para abrir el comprobante.' });
    } catch (error) {
      if (classifySaleFailure(error) === 'unknown') {
        setStatus(SALE_STATUS.UNKNOWN);
        setMessage({ variant: 'warning', title: 'Resultado desconocido', text: 'No se recibió una confirmación concluyente. La solicitud quedó bloqueada; consulta su resultado con la misma clave antes de repetirla.' });
      } else {
        setStatus(SALE_STATUS.REJECTED);
        setQuote(null);
        setIdempotencyKey(newKey());
        setAttempted(false);
        setMessage({ variant: error.status === 409 ? 'warning' : 'error', title: error.status === 409 ? 'Venta en conflicto' : 'Venta rechazada', text: errorMessage(error) });
      }
    } finally { setBusy(false); }
  };

  const resolveUnknown = async () => {
    setBusy(true); setMessage(null);
    try {
      const response = await salesApi.result(idempotencyKey);
      const result = response.data || {};
      const { outcome, saleId } = saleResultOutcome(result);
      if (outcome === 'confirmed') {
        setStatus(SALE_STATUS.CONFIRMED);
        if (saleId) { allowNavigationRef.current = true; navigate(`/ventas/${saleId}`, { replace: true }); }
        else setMessage({ variant: 'success', title: 'Venta confirmada', text: 'Consulta Mis ventas para abrir el comprobante.' });
      } else if (outcome === 'rejected') {
        setStatus(SALE_STATUS.REJECTED);
        setQuote(null);
        setIdempotencyKey(newKey());
        setAttempted(false);
        setMessage({ variant: 'warning', title: 'Venta rechazada', text: 'El servidor confirmó que la venta no se registró. Revisa la cotización antes de intentarlo de nuevo.' });
      } else {
        setMessage({ variant: 'warning', title: 'Resultado aún pendiente', text: 'El servidor todavía no tiene un resultado concluyente. No repitas la venta.' });
      }
    } catch (error) {
      setMessage({ variant: 'warning', title: 'No se pudo resolver aún', text: `${errorMessage(error)} La ausencia momentánea de una factura no demuestra que la operación se haya revertido.` });
    } finally { setBusy(false); }
  };

  const quoteLines = normalizeList(quote?.lines || quote?.details || quote?.detalle || []);
  const totals = quote?.totals || {};
  const currency = firstDefined(totals, ['currency', 'moneda']);
  const quoteLine = (line) => quoteLines.find((item) => String(firstDefined(item, ['productId', 'productoId', 'id'])) === String(entityId(line.product)));

  return (
    <>
      <PageHeader title="Nueva venta" description="La cotización y el registro se validan en SQL Server. Ningún precio o total del navegador se considera confiable." actions={<StatusBadge value={status} />} />
      {message && <InlineAlert variant={message.variant} title={message.title}>{message.text}{status === SALE_STATUS.UNKNOWN && <div className="alert-actions"><button type="button" className="button button--secondary button--small" disabled={busy} onClick={resolveUnknown}><RefreshCw size={16} /> {busy ? 'Consultando…' : 'Consultar resultado'}</button></div>}</InlineAlert>}
      {cart.length > 0 && !locked && <InlineAlert variant="info" title="Cambios sin guardar">Este borrador existe solo en memoria y se perderá al salir de la página.</InlineAlert>}
      <div className="sale-layout">
        <div className="sale-main">
          <section className="panel sale-step" aria-labelledby="customer-step">
            <div className="step-heading"><span>1</span><div><h2 id="customer-step">Cliente</h2><p>Selecciona un cliente activo.</p></div></div>
            {customer ? <div className="selected-entity"><UserRound aria-hidden="true" /><div><strong>{firstDefined(customer, ['name', 'nombre', 'businessName', 'razonSocial'])}</strong><small>{firstDefined(customer, ['identifier', 'taxId', 'identification', 'nit', 'identificacion'], 'Sin identificación')}</small></div><button type="button" className="button button--ghost button--small" disabled={locked} onClick={() => { setCustomer(null); invalidateQuote(); }}>Cambiar</button></div> : <>
              <form className="inline-search" onSubmit={findCustomers}><label className="sr-only" htmlFor="sale-customer-search">Buscar cliente</label><div className="input-with-icon"><Search size={17} /><input id="sale-customer-search" value={customerSearch} maxLength="160" onChange={(event) => setCustomerSearch(event.target.value)} placeholder="Nombre o identificación" disabled={locked} /></div><button className="button button--secondary" type="submit" disabled={locked || customerResults.status === 'loading'}>Buscar</button></form>
              <SearchResults state={customerResults} empty="No se encontraron clientes activos.">{(item) => <button type="button" disabled={locked} onClick={() => selectCustomer(item)}><span><strong>{firstDefined(item, ['name', 'nombre', 'businessName', 'razonSocial'])}</strong><small>{firstDefined(item, ['identifier', 'taxId', 'identification', 'nit', 'identificacion'], 'Sin identificación')}</small></span><Check size={17} /></button>}</SearchResults>
            </>}
          </section>

          <section className="panel sale-step" aria-labelledby="products-step">
            <div className="step-heading"><span>2</span><div><h2 id="products-step">Productos</h2><p>Agrega hasta 100 productos distintos.</p></div></div>
            <form className="inline-search" onSubmit={findProducts}><label className="sr-only" htmlFor="sale-product-search">Buscar producto</label><div className="input-with-icon"><Search size={17} /><input id="sale-product-search" value={productSearch} maxLength="160" onChange={(event) => setProductSearch(event.target.value)} placeholder="Código o descripción" disabled={locked} /></div><button className="button button--secondary" type="submit" disabled={locked || productResults.status === 'loading'}>Buscar</button></form>
            <SearchResults state={productResults} empty="No se encontraron productos activos.">{(item) => <button type="button" onClick={() => addProduct(item)} disabled={locked || Number(firstDefined(item, ['stock', 'existencia'], 0)) <= 0}><span><strong>{firstDefined(item, ['code', 'codigo'])} · {firstDefined(item, ['description', 'descripcion', 'name', 'nombre'])}</strong><small>Existencia: {firstDefined(item, ['stock', 'existencia'], 0)}</small></span><Plus size={17} /></button>}</SearchResults>
            {!cart.length ? <EmptyState title="Venta sin productos">Busca y agrega el primer producto.</EmptyState> : <TableWrap label="Detalle de la venta"><table className="sale-lines"><thead><tr><th>Producto</th><th className="numeric">Cantidad</th><th className="numeric">Precio</th><th className="numeric">Importe</th><th><span className="sr-only">Quitar</span></th></tr></thead><tbody>
              {cart.map((line) => { const priced = quoteLine(line); return <tr key={entityId(line.product)}><td><strong>{firstDefined(line.product, ['code', 'codigo'])}</strong><small>{firstDefined(line.product, ['description', 'descripcion', 'name', 'nombre'])}</small></td><td className="numeric"><div className="quantity-control"><button type="button" className="icon-button" disabled={locked || line.quantity <= 1} onClick={() => changeQuantity(entityId(line.product), line.quantity - 1)} aria-label="Restar unidad"><Minus size={15} /></button><input aria-label={`Cantidad de ${firstDefined(line.product, ['description', 'descripcion'])}`} type="number" min="1" max="9999" value={line.quantity} disabled={locked} onChange={(event) => changeQuantity(entityId(line.product), event.target.value)} /><button type="button" className="icon-button" disabled={locked || line.quantity >= 9999} onClick={() => changeQuantity(entityId(line.product), line.quantity + 1)} aria-label="Sumar unidad"><Plus size={15} /></button></div></td><td className="numeric tabular">{priced ? formatMoney(firstDefined(priced, ['unitPrice', 'price', 'precioUnitario']), currency) : 'Por cotizar'}</td><td className="numeric tabular">{priced ? formatMoney(firstDefined(priced, ['lineTotal', 'subtotal', 'importe']), currency) : '—'}</td><td className="actions-cell"><button type="button" className="icon-button icon-button--danger" disabled={locked} onClick={() => removeProduct(entityId(line.product))} aria-label="Quitar producto"><Trash2 size={17} /></button></td></tr>; })}
            </tbody></table></TableWrap>}
          </section>
        </div>

        <aside className="panel sale-summary" aria-labelledby="sale-summary-title">
          <div className="panel__header"><div><p className="eyebrow">Paso 3</p><h2 id="sale-summary-title">Resumen</h2></div><ShoppingCart aria-hidden="true" /></div>
          <dl className="summary-totals"><div><dt>Productos</dt><dd>{cart.length}</dd></div><div><dt>Unidades</dt><dd>{cart.reduce((sum, line) => sum + line.quantity, 0)}</dd></div><div><dt>Subtotal</dt><dd>{quote ? formatMoney(firstDefined(totals, ['subtotal']), currency) : '—'}</dd></div><div><dt>IVA ({firstDefined(totals, ['taxRate', 'tasaImpuesto'], '12')}%)</dt><dd>{quote ? formatMoney(firstDefined(totals, ['tax', 'iva']), currency) : '—'}</dd></div><div className="summary-total"><dt>Total</dt><dd>{quote ? formatMoney(firstDefined(totals, ['total']), currency) : '—'}</dd></div></dl>
          {!quote && <button type="button" className="button button--primary button--block" disabled={!customer || !cart.length || busy || locked} onClick={requestQuote}>{busy ? 'Cotizando…' : 'Cotizar venta'}</button>}
          {quote && status === SALE_STATUS.READY && <button type="button" className="button button--primary button--block" disabled={busy} onClick={() => setConfirmOpen(true)}>Confirmar venta</button>}
          {quote && !locked && <button type="button" className="button button--ghost button--block" disabled={busy} onClick={requestQuote}><RefreshCw size={16} /> Actualizar cotización</button>}
          <p className="summary-note">El servidor recalcula importes, comprueba existencias y registra factura, caja y auditoría en una sola transacción.</p>
        </aside>
      </div>
      <ConfirmDialog open={confirmOpen} title="Confirmar venta" confirmLabel="Registrar venta" busy={busy} onClose={() => setConfirmOpen(false)} onConfirm={confirmSale}>Se registrará una factura por {quote ? formatMoney(firstDefined(totals, ['total']), currency) : '—'}. Esta acción no puede editarse después.</ConfirmDialog>
      <ConfirmDialog open={blocker.state === 'blocked'} title={status === SALE_STATUS.UNKNOWN ? 'El resultado de la venta sigue pendiente' : 'Hay una venta sin guardar'} confirmLabel={status === SALE_STATUS.UNKNOWN ? 'Salir de todos modos' : 'Salir y descartar'} danger onClose={() => blocker.reset?.()} onConfirm={() => blocker.proceed?.()}>{status === SALE_STATUS.UNKNOWN ? 'Si sales ahora ya no podrás consultar el resultado desde este borrador. No repitas la venta sin verificar antes la factura.' : 'El borrador existe solo en memoria. Si sales ahora se perderán el cliente, los productos y la cotización.'}</ConfirmDialog>
    </>
  );
}

function SearchResults({ state, empty, children }) {
  if (state.status === 'idle') return null;
  if (state.status === 'loading') return <p className="search-status" role="status">Buscando…</p>;
  if (state.status === 'error') return <InlineAlert variant="error">{errorMessage(state.error)}</InlineAlert>;
  if (!state.items.length) return <p className="search-status">{empty}</p>;
  return <div className="search-results">{state.items.map((item) => <div key={entityId(item)}>{children(item)}</div>)}</div>;
}
