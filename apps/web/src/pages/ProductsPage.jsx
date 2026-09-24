import { useCallback, useEffect, useMemo, useState } from 'react';
import { PackagePlus, Pencil, Search, SlidersHorizontal } from 'lucide-react';
import { productsApi } from '../api/endpoints.js';
import { ApiError, errorMessage } from '../api/client.js';
import { useAuth } from '../contexts/AuthContext.jsx';
import { Modal } from '../components/Modal.jsx';
import { EmptyState, ErrorState, FieldError, InlineAlert, PageHeader, PageLoader, Pagination, StatusBadge, TableWrap } from '../components/Ui.jsx';
import { entityId, firstDefined, formatMoney, normalizeList } from '../utils/format.js';
import { hasPermission, PERMISSIONS } from '../utils/permissions.js';

const EMPTY_PRODUCT = { code: '', description: '', unit: '', price: '', active: true };

export default function ProductsPage() {
  const { user } = useAuth();
  const canManage = hasPermission(user, PERMISSIONS.PRODUCTS);
  const [filters, setFilters] = useState({ search: '', status: 'active', page: 1, pageSize: 25 });
  const [query, setQuery] = useState(filters);
  const [state, setState] = useState({ status: 'loading', items: [], total: 0, error: null });
  const [optionsState, setOptionsState] = useState({ status: canManage ? 'loading' : 'unavailable', items: [], error: null });
  const [editor, setEditor] = useState(null);
  const [inventoryProduct, setInventoryProduct] = useState(null);

  const load = useCallback(async (signal) => {
    setState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await productsApi.list(query, signal);
      const items = normalizeList(response.data);
      setState({ status: 'ready', items, total: response.meta?.total ?? response.data?.total ?? items.length, error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setState((current) => ({ ...current, status: 'error', error }));
    }
  }, [query]);

  useEffect(() => {
    const controller = new AbortController();
    load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const loadOptions = useCallback(async (signal) => {
    if (!canManage) return;
    setOptionsState((current) => ({ ...current, status: 'loading', error: null }));
    try {
      const response = await productsApi.options(signal);
      setOptionsState({ status: 'ready', items: normalizeList(response.data), error: null });
    } catch (error) {
      if (error?.name !== 'AbortError') setOptionsState({ status: 'error', items: [], error });
    }
  }, [canManage]);

  useEffect(() => {
    const controller = new AbortController();
    void loadOptions(controller.signal);
    return () => controller.abort();
  }, [loadOptions]);

  const submitFilters = (event) => {
    event.preventDefault();
    setQuery({ ...filters, page: 1 });
    setFilters((current) => ({ ...current, page: 1 }));
  };

  const changePage = (page) => {
    const next = { ...query, page };
    setFilters(next);
    setQuery(next);
  };
  const changePageSize = (pageSize) => {
    const next = { ...query, page: 1, pageSize };
    setFilters(next);
    setQuery(next);
  };
  const reload = () => setQuery((current) => ({ ...current }));

  return (
    <>
      <PageHeader
        title="Productos"
        description={canManage ? 'Administra precios, estado y existencias mediante ajustes trazables.' : 'Consulta productos activos y disponibilidad para ventas.'}
        actions={canManage && <button type="button" className="button button--primary" onClick={() => setEditor(EMPTY_PRODUCT)} disabled={optionsState.status !== 'ready' || !optionsState.items.length}><PackagePlus size={18} /> Nuevo producto</button>}
      />
      {optionsState.status === 'error' && <InlineAlert variant="warning" title="No se cargaron las unidades" onRetry={() => loadOptions()}>No se puede crear un producto hasta recuperar el catálogo de unidades. {errorMessage(optionsState.error)}</InlineAlert>}
      {optionsState.status === 'ready' && !optionsState.items.length && <InlineAlert variant="warning" title="Catálogo de unidades vacío">Configura al menos una unidad de medida antes de crear productos.</InlineAlert>}
      <section className="panel">
        <form className="filter-bar" onSubmit={submitFilters} role="search">
          <div className="field field--grow">
            <label htmlFor="product-search">Buscar producto</label>
            <div className="input-with-icon"><Search size={17} /><input id="product-search" value={filters.search} maxLength="160" onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} placeholder="Código o descripción" /></div>
          </div>
          <div className="field">
            <label htmlFor="product-status">Estado</label>
            <select id="product-status" value={filters.status} onChange={(event) => setFilters((current) => ({ ...current, status: event.target.value }))}>
              <option value="active">Activos</option><option value="inactive">Inactivos</option><option value="all">Todos</option>
            </select>
          </div>
          <button type="submit" className="button button--secondary"><Search size={17} /> Buscar</button>
        </form>

        {state.status === 'loading' && <PageLoader label="Cargando productos…" />}
        {state.status === 'error' && <ErrorState error={state.error} onRetry={reload} />}
        {state.status === 'ready' && state.items.length === 0 && <EmptyState search={Boolean(query.search)}>{query.search ? 'Prueba con otro código o descripción.' : 'Crea el primer producto para comenzar.'}</EmptyState>}
        {state.status === 'ready' && state.items.length > 0 && (
          <>
            <TableWrap label="Listado de productos">
              <table>
                <thead><tr><th>Código</th><th>Descripción</th><th>Unidad</th><th className="numeric">Precio sin IVA</th><th className="numeric">Existencia</th><th>Estado</th>{canManage && <th className="actions-cell">Acciones</th>}</tr></thead>
                <tbody>
                  {state.items.map((product) => (
                    <tr key={entityId(product)}>
                      <td><strong>{firstDefined(product, ['code', 'codigo'])}</strong></td>
                      <td>{firstDefined(product, ['description', 'descripcion', 'name', 'nombre'])}</td>
                      <td>{firstDefined(product, ['unit', 'unidad'], 'Unidad')}</td>
                      <td className="numeric tabular">{formatMoney(firstDefined(product, ['price', 'precio'], '0.00'), firstDefined(product, ['currency', 'moneda']))}</td>
                      <td className="numeric tabular">{firstDefined(product, ['stock', 'existencia'], '0')}</td>
                      <td><StatusBadge value={(product.active ?? product.activo) === false ? 'Inactivo' : 'Activo'} /></td>
                      {canManage && <td className="actions-cell"><div className="row-actions"><button className="icon-button" type="button" onClick={() => setEditor(product)} aria-label={`Editar ${firstDefined(product, ['description', 'descripcion'])}`}><Pencil size={17} /></button><button className="icon-button" type="button" onClick={() => setInventoryProduct(product)} aria-label={`Ajustar inventario de ${firstDefined(product, ['description', 'descripcion'])}`}><SlidersHorizontal size={17} /></button></div></td>}
                    </tr>
                  ))}
                </tbody>
              </table>
            </TableWrap>
            <Pagination page={query.page} pageSize={query.pageSize} total={state.total} onPageChange={changePage} onPageSizeChange={changePageSize} />
          </>
        )}
      </section>
      <ProductEditor product={editor} unitOptions={optionsState.items} optionsReady={optionsState.status === 'ready'} onClose={() => setEditor(null)} onSaved={() => { setEditor(null); reload(); }} />
      <InventoryEditor product={inventoryProduct} onClose={() => setInventoryProduct(null)} onSaved={() => { setInventoryProduct(null); reload(); }} />
    </>
  );
}

function ProductEditor({ product, unitOptions, optionsReady, onClose, onSaved }) {
  const isOpen = Boolean(product);
  const isNew = product === EMPTY_PRODUCT;
  const initial = useMemo(() => product ? ({
    code: firstDefined(product, ['code', 'codigo']),
    description: firstDefined(product, ['description', 'descripcion', 'name', 'nombre']),
    unit: firstDefined(product, ['unit', 'unidad'], 'Unidad'),
    price: String(firstDefined(product, ['price', 'precio'])),
    active: (product.active ?? product.activo) !== false,
  }) : EMPTY_PRODUCT, [product]);
  const [values, setValues] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const currentUnitAvailable = unitOptions.some((option) => String(option.code) === String(values.unit));

  useEffect(() => { setValues(initial); setError(null); }, [initial]);
  const update = (event) => {
    const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
    setValues((current) => ({ ...current, [event.target.name]: value }));
  };
  const submit = async (event) => {
    event.preventDefault();
    setBusy(true); setError(null);
    try {
      if (isNew) {
        await productsApi.create({ code: values.code, description: values.description, unit: values.unit, price: values.price });
      } else {
        await productsApi.update(entityId(product), { ...values, price: values.price, version: product?.version ?? product?.rowVersion });
      }
      onSaved();
    } catch (nextError) { setError(nextError); setBusy(false); }
  };

  return (
    <Modal open={isOpen} title={isNew ? 'Nuevo producto' : 'Editar producto'} description="El precio se registra sin IVA. Los productos nuevos comienzan con existencia cero." onClose={onClose} footer={<><button className="button button--secondary" type="button" onClick={onClose} disabled={busy}>Cancelar</button><button className="button button--primary" type="submit" form="product-form" disabled={busy || !optionsReady}>{busy ? 'Guardando…' : 'Guardar producto'}</button></>}>
      {error && <InlineAlert variant={error instanceof ApiError && error.status === 409 ? 'warning' : 'error'} title={error?.status === 409 ? 'Edición concurrente' : 'No se pudo guardar'}>{errorMessage(error)}</InlineAlert>}
      <form id="product-form" className="form-grid" onSubmit={submit}>
        <div className="field"><label htmlFor="product-code">Código</label><input id="product-code" name="code" value={values.code} onChange={update} required maxLength="30" disabled={busy || !isNew} /></div>
        <div className="field"><label htmlFor="product-unit">Unidad</label><select id="product-unit" name="unit" value={values.unit} onChange={update} required disabled={busy || !optionsReady}><option value="">Selecciona una unidad</option>{values.unit && !currentUnitAvailable && <option value={values.unit}>{values.unit} (actual)</option>}{unitOptions.map((option) => <option key={option.code} value={option.code}>{option.name || option.code}</option>)}</select></div>
        <div className="field field--span"><label htmlFor="product-description">Descripción</label><input id="product-description" name="description" value={values.description} onChange={update} required maxLength="160" disabled={busy} /></div>
        <div className="field"><label htmlFor="product-price">Precio sin IVA</label><input id="product-price" name="price" type="text" inputMode="decimal" pattern="(?:0|[1-9]\d{0,5})\.\d{2}" placeholder="0.00" value={values.price} onChange={update} required disabled={busy} aria-describedby="product-price-help" /><span className="field-help" id="product-price-help">Entre 0.01 y 999999.99; escribe dos decimales.</span></div>
        {!isNew && <label className="check-field"><input type="checkbox" name="active" checked={values.active} onChange={update} disabled={busy} /> Producto activo</label>}
      </form>
    </Modal>
  );
}

function InventoryEditor({ product, onClose, onSaved }) {
  const [quantityChange, setQuantityChange] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  useEffect(() => { setQuantityChange(''); setReason(''); setError(null); }, [product]);
  const numericChange = Number(quantityChange);
  const valid = /^-?\d+$/.test(quantityChange) && numericChange !== 0 && Math.abs(numericChange) <= 999999 && reason.trim().length >= 10 && reason.trim().length <= 250;
  const submit = async (event) => {
    event.preventDefault();
    if (!valid) return;
    setBusy(true); setError(null);
    try {
      await productsApi.inventory(entityId(product), { delta: Number(quantityChange), reason, version: product?.version ?? product?.rowVersion });
      onSaved();
    } catch (nextError) { setError(nextError); setBusy(false); }
  };
  return (
    <Modal open={Boolean(product)} title="Ajustar inventario" description={product ? `${firstDefined(product, ['code', 'codigo'])} · Existencia actual: ${firstDefined(product, ['stock', 'existencia'], 0)}` : ''} onClose={onClose} footer={<><button type="button" className="button button--secondary" onClick={onClose} disabled={busy}>Cancelar</button><button type="submit" form="inventory-form" className="button button--primary" disabled={!valid || busy}>{busy ? 'Aplicando…' : 'Aplicar ajuste'}</button></>}>
      {error && <InlineAlert variant={error?.status === 409 ? 'warning' : 'error'} title={error?.status === 409 ? 'La existencia cambió' : 'No se pudo ajustar'}>{errorMessage(error)}</InlineAlert>}
      <form id="inventory-form" className="form-stack" onSubmit={submit}>
        <div className="field"><label htmlFor="quantity-change">Cambio de unidades</label><input id="quantity-change" type="number" step="1" min="-999999" max="999999" value={quantityChange} onChange={(event) => setQuantityChange(event.target.value)} required disabled={busy} /><span className="field-help">Usa un valor positivo para entrada y negativo para salida. La existencia nunca puede quedar negativa.</span></div>
        <div className="field"><label htmlFor="inventory-reason">Motivo</label><textarea id="inventory-reason" value={reason} onChange={(event) => setReason(event.target.value)} minLength="10" maxLength="250" rows="4" required disabled={busy} aria-describedby="inventory-reason-error" /><FieldError id="inventory-reason-error" error={reason && reason.trim().length < 10 ? 'Escribe al menos 10 caracteres útiles.' : null} /></div>
      </form>
    </Modal>
  );
}
