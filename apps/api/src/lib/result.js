export function firstRow(result) {
  return result.recordsets?.[0]?.[0] ?? null;
}

export function listResult(result) {
  const rows = result.recordsets?.[0] ?? [];
  const summary = result.recordsets?.[1]?.[0] ?? {};
  return {
    data: rows,
    meta: {
      page: summary.page ?? 1,
      pageSize: summary.pageSize ?? rows.length,
      total: summary.total ?? rows.length,
      totalPages: summary.totalPages ?? (rows.length ? 1 : 0),
    },
  };
}

export function saleResult(result) {
  return {
    lines: result.recordsets?.[0] ?? [],
    totals: result.recordsets?.[1]?.[0] ?? null,
  };
}
