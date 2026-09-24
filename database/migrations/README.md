# Migraciones

`install.sql` representa la linea base `0001_baseline`. Cada cambio posterior debe agregarse como un archivo numerado, por ejemplo `0002_agregar_indice.sql`, y terminar insertando su identificador en `dbo.SchemaMigration` solo despues de completar la transaccion.

Migraciones incluidas:

- `0002_security_contract_hardening.sql`: retira del rol administrador protegido el permiso de venta que la linea base concedia por error, elimina texto DDL legado que pudiera contener secretos y registra el endurecimiento de contratos. `install.sql` la ejecuta despues de actualizar los modulos con `CREATE OR ALTER`.

Reglas:

1. Comprobar primero `dbo.SchemaMigration`; una migracion aplicada no vuelve a ejecutarse.
2. Usar `XACT_ABORT ON` y `TRY/CATCH` para cambios transaccionales.
3. Agregar columnas inicialmente anulables o con un valor predeterminado seguro; poblarlas antes de endurecer restricciones.
4. No usar `DROP DATABASE`, truncados, borrado masivo ni resiembra como mecanismo de actualizacion.
5. Crear una copia completa antes de migrar y ensayar restauracion en otra base.
6. El proceso de despliegue ejecuta migraciones; la API nunca lo hace al arrancar.

La plantilla `migration-template.sql.example` ilustra el patron esperado.
