import { sql, input } from '../db/database.js';

export function pageParameters(query) {
  return {
    Pagina: input(sql.Int, query.page),
    TamanoPagina: input(sql.TinyInt, query.pageSize),
    Busqueda: input(sql.NVarChar(160), query.search || null),
    Orden: input(sql.VarChar(40), query.sort ?? null),
    Direccion: input(sql.VarChar(4), query.direction),
  };
}

export function rowVersionBuffer(value) {
  return Buffer.from(value.slice(2), 'hex');
}
