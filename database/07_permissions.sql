USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_VerificarEstado
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.ConfiguracionSistema
        WHERE ConfiguracionId=1
          AND LEN(MonedaCodigo)=3
          AND NULLIF(ZonaHorariaIana,N'') IS NOT NULL
          AND NULLIF(ZonaHorariaSql,N'') IS NOT NULL
          AND TasaIVA BETWEEN 0 AND 1
    )
        THROW 51006,N'La configuracion del sistema no esta disponible.',1;

    SELECT 'available' AS databaseStatus,SYSUTCDATETIME() AS databaseUtc,
           c.MonedaCodigo AS currency,c.ZonaHorariaIana AS timeZone
    FROM dbo.ConfiguracionSistema c WHERE c.ConfiguracionId=1;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'SecureFinanceApiExecutor') IS NULL
    CREATE ROLE SecureFinanceApiExecutor AUTHORIZATION dbo;
GO

DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO SecureFinanceApiExecutor;
/* CONTROL incluye EXECUTE y anularía los GRANT mínimos por objeto. */
REVOKE CONTROL ON SCHEMA::dbo FROM SecureFinanceApiExecutor;
DENY ALTER, TAKE OWNERSHIP ON SCHEMA::dbo TO SecureFinanceApiExecutor;
GO

GRANT EXECUTE ON OBJECT::dbo.sp_AutenticarUsuario TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_VerificarEstado TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ValidarSesionApi TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_CerrarSesion TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_SolicitarRecuperacion TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_RestablecerPassword TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarPerfil TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerPreferenciasUsuario TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_GuardarPreferenciasUsuario TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_CambiarPassword TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ListarUsuarios TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_CrearUsuario TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarUsuario TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_GenerarPasswordTemporal TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ListarRoles TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_CrearRol TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarRol TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ListarPermisos TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ListarUnidadesMedida TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ListarProductos TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_CrearProducto TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarProducto TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_AjustarInventario TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ListarClientes TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_CrearCliente TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarCliente TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_CotizarVenta TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaTransaccional TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarResultadoVenta TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarVentasPropias TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarFactura TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerHistoricoVentas TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerResumenInicio TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarBitacoraAcceso TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarAuditoriaDML TO SecureFinanceApiExecutor;
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarAuditoriaDDL TO SecureFinanceApiExecutor;
GRANT REFERENCES ON TYPE::dbo.TVP_DetalleFactura TO SecureFinanceApiExecutor;
GRANT REFERENCES ON TYPE::dbo.TVP_ListaEnteros TO SecureFinanceApiExecutor;
GRANT REFERENCES ON TYPE::dbo.TVP_CodigosPermiso TO SecureFinanceApiExecutor;
GRANT EXECUTE ON TYPE::dbo.TVP_DetalleFactura TO SecureFinanceApiExecutor;
GRANT EXECUTE ON TYPE::dbo.TVP_ListaEnteros TO SecureFinanceApiExecutor;
GRANT EXECUTE ON TYPE::dbo.TVP_CodigosPermiso TO SecureFinanceApiExecutor;
GO

IF OBJECT_ID(N'dbo.SchemaMigration',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SchemaMigration
    (
        MigrationId varchar(100) NOT NULL CONSTRAINT PK_SchemaMigration PRIMARY KEY,
        Descripcion nvarchar(250) NOT NULL,
        AplicadaUtc datetime2(3) NOT NULL CONSTRAINT DF_SchemaMigration_AplicadaUtc DEFAULT(SYSUTCDATETIME()),
        AplicadaPor sysname NOT NULL CONSTRAINT DF_SchemaMigration_AplicadaPor DEFAULT(SUSER_SNAME())
    );
END;
IF NOT EXISTS(SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId='0001_baseline')
    INSERT dbo.SchemaMigration(MigrationId,Descripcion) VALUES('0001_baseline',N'Esquema funcional inicial SecureFinance ERP 2.0');
GO
