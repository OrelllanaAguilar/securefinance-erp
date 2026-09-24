import { useCallback, useEffect, useState } from 'react';
import { ArrowLeft, Printer } from 'lucide-react';
import { Link, useParams } from 'react-router';
import { salesApi } from '../api/endpoints.js';
import { ErrorState, PageHeader, PageLoader, StatusBadge, TableWrap } from '../components/Ui.jsx';
import { firstDefined, formatDate, formatMoney, normalizeList } from '../utils/format.js';

export default function SaleDetailPage() {
  const { id } = useParams();
  const [state, setState] = useState({ status: 'loading', sale: null, error: null });
  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await salesApi.get(id, signal);
      setState({ status: 'ready', sale: response.data, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState({ status: 'error', sale: null, error });
    }
  }, [id]);
  useEffect(() => { const controller = new AbortController(); load(controller.signal); return () => controller.abort(); }, [load]);

  return (
    <>
      <div className="print-hidden"><PageHeader title="Comprobante de venta" description="Documento interno de solo lectura. Imprimirlo no registra una venta nueva." actions={<div className="button-group"><Link className="button button--secondary" to="/ventas"><ArrowLeft size={17} /> Volver</Link>{state.sale && <button type="button" className="button button--primary" onClick={() => window.print()}><Printer size={17} /> Imprimir</button>}</div>} /></div>
      {state.status === 'loading' && <PageLoader label="Cargando comprobante…" />}
      {state.status === 'error' && <ErrorState error={state.error} onRetry={() => load()} title="No se pudo cargar el comprobante" />}
      {state.status === 'ready' && <Receipt sale={state.sale} />}
    </>
  );
}

function Receipt({ sale }) {
  const lines = normalizeList(sale?.lines || sale?.details || sale?.detalle || []);
  const currency = firstDefined(sale, ['currency', 'moneda']);
  return (
    <article className="receipt" aria-label="Comprobante de venta">
      <header className="receipt__header">
        <div><div className="brand brand--receipt"><span className="brand__mark">SF</span><span><strong>SecureFinance ERP</strong><small>Comprobante interno</small></span></div></div>
        <div className="receipt__number"><span>Factura</span><strong>{firstDefined(sale, ['number', 'invoiceNumber', 'numeroFactura'], firstDefined(sale, ['id', 'saleId']))}</strong><StatusBadge value={firstDefined(sale, ['status', 'estado'], 'Confirmada')} /></div>
      </header>
      <section className="receipt__meta">
        <dl>
          <div><dt>Fecha</dt><dd>{formatDate(firstDefined(sale, ['issuedAt', 'createdAt', 'date', 'fecha']), { includeTime: true })}</dd></div>
          <div><dt>Cliente</dt><dd>{firstDefined(sale, ['customerName', 'clienteNombre', 'customerSnapshot'], 'Consumidor final')}</dd></div>
          <div><dt>Identificación</dt><dd>{firstDefined(sale, ['customerIdentifier', 'customerTaxId', 'clienteIdentificacion', 'taxId'], '—')}</dd></div>
          <div><dt>Cajero</dt><dd>{firstDefined(sale, ['cashierName', 'cajeroNombre', 'cashierSnapshot'], '—')}</dd></div>
          <div><dt>Moneda</dt><dd>{currency}</dd></div>
        </dl>
      </section>
      <TableWrap label="Detalle del comprobante"><table className="receipt-table"><thead><tr><th>Código</th><th>Descripción</th><th>Unidad</th><th className="numeric">Cantidad</th><th className="numeric">Precio</th><th className="numeric">Importe</th></tr></thead><tbody>
        {lines.map((line, index) => <tr key={firstDefined(line, ['id', 'productId', 'codigo'], index)}><td>{firstDefined(line, ['code', 'codigo'])}</td><td>{firstDefined(line, ['description', 'descripcion'])}</td><td>{firstDefined(line, ['unit', 'unidad'], 'Unidad')}</td><td className="numeric tabular">{firstDefined(line, ['quantity', 'cantidad'])}</td><td className="numeric tabular">{formatMoney(firstDefined(line, ['unitPrice', 'price', 'precioUnitario'], '0.00'), currency)}</td><td className="numeric tabular">{formatMoney(firstDefined(line, ['lineTotal', 'subtotal', 'importe'], '0.00'), currency)}</td></tr>)}
      </tbody></table></TableWrap>
      <section className="receipt__totals" aria-label="Totales">
        <dl><div><dt>Subtotal</dt><dd>{formatMoney(firstDefined(sale, ['subtotal'], '0.00'), currency)}</dd></div><div><dt>IVA ({firstDefined(sale, ['taxRate', 'tasaImpuesto'], '12')}%)</dt><dd>{formatMoney(firstDefined(sale, ['tax', 'iva'], '0.00'), currency)}</dd></div><div className="receipt__grand-total"><dt>Total</dt><dd>{formatMoney(firstDefined(sale, ['total'], '0.00'), currency)}</dd></div></dl>
      </section>
      <footer className="receipt__footer">Este comprobante refleja los datos históricos guardados al confirmar la venta.</footer>
    </article>
  );
}
