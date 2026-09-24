const DEFAULT_LOCALE = 'es-GT';
let runtimeCurrency = 'GTQ';
let runtimeTimeZone = 'America/Guatemala';

export function setFormattingConfig({ currency, timeZone } = {}) {
  if (/^[A-Z]{3}$/u.test(currency ?? '')) runtimeCurrency = currency;
  if (typeof timeZone === 'string' && timeZone) runtimeTimeZone = timeZone;
}

export function formatMoney(value, currency = runtimeCurrency, locale = DEFAULT_LOCALE) {
  if (value === null || value === undefined || value === '') return '—';
  const displayedCurrency = /^[A-Z]{3}$/u.test(currency ?? '') ? currency : runtimeCurrency;
  const text = String(value);
  const match = /^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(text);
  if (!match) return `${text} ${displayedCurrency}`;
  const [, sign, rawInteger, rawFraction = ''] = match;
  const integer = rawInteger.replace(/^0+(?=\d)/, '');
  const parts = new Intl.NumberFormat(locale).formatToParts(1000.1);
  const group = parts.find((part) => part.type === 'group')?.value || ',';
  const decimal = parts.find((part) => part.type === 'decimal')?.value || '.';
  const grouped = integer.replace(/\B(?=(\d{3})+(?!\d))/g, group);
  const fraction = rawFraction.padEnd(2, '0');
  return `${displayedCurrency}\u00a0${sign}${grouped}${decimal}${fraction}`;
}

export function formatDate(value, { includeTime = false, timeZone = runtimeTimeZone } = {}) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat(DEFAULT_LOCALE, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    ...(includeTime ? { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' } : {}),
    timeZone,
  }).format(date);
}

export function configuredDateInput(dayOffset = 0, value = new Date()) {
  const parts = new Intl.DateTimeFormat('en', {
    timeZone: runtimeTimeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(value);
  const fields = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const date = new Date(Date.UTC(Number(fields.year), Number(fields.month) - 1, Number(fields.day)));
  date.setUTCDate(date.getUTCDate() + dayOffset);
  return date.toISOString().slice(0, 10);
}

export function normalizeList(payload) {
  if (Array.isArray(payload)) return payload;
  return payload?.items || payload?.rows || payload?.records || [];
}

export function entityId(entity) {
  return entity?.id ?? entity?.productId ?? entity?.customerId ?? entity?.saleId ?? entity?.userId ?? entity?.roleId;
}

export function firstDefined(object, keys, fallback = '') {
  for (const key of keys) if (object?.[key] !== undefined && object?.[key] !== null) return object[key];
  return fallback;
}

export function embeddedList(value) {
  if (Array.isArray(value)) return value;
  if (typeof value !== 'string' || !value) return [];
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
