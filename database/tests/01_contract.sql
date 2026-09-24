:on error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;

DECLARE @Faltantes TABLE(Tipo varchar(20),Nombre sysname);
DECLARE @Tablas TABLE(Nombre sysname);
INSERT @Tablas VALUES
 ('Usuario'),('Usuario_Rol'),('Rol'),('Rol_Permiso'),('Permiso'),('Sesion'),('TokenRecuperacion'),
 ('PreferenciaUsuario'),('UnidadMedida'),('Cliente'),('Producto'),('MovimientoInventario'),
 ('Factura'),('Detalle_Factura'),('MovimientoCaja'),('Bitacora_Acceso'),('Bitacora_Transacciones'),
 ('Bitacora_DDL'),('Bitacora_Incidente'),('ConfiguracionSistema'),('SchemaMigration');
INSERT @Faltantes SELECT 'TABLE',Nombre FROM @Tablas WHERE OBJECT_ID(N'dbo.'+Nombre,N'U') IS NULL;

DECLARE @Procedimientos TABLE(Nombre sysname);
INSERT @Procedimientos VALUES
 ('sp_LimpiarContextoAuditoria'),('sp_RegistrarAcceso'),('sp_ResolverSesion'),
 ('sp_VerificarEstado'),('sp_AutenticarUsuario'),('sp_ValidarSesionApi'),('sp_CerrarSesion'),
 ('sp_CambiarPassword'),('sp_SolicitarRecuperacion'),('sp_ValidarTokenRecuperacion'),('sp_RestablecerPassword'),
 ('sp_ConsultarPerfil'),('sp_ObtenerPermisosUsuario'),('sp_ObtenerPreferenciasUsuario'),('sp_GuardarPreferenciasUsuario'),
 ('sp_ListarUnidadesMedida'),('sp_ListarProductos'),('sp_CrearProducto'),('sp_ActualizarProducto'),('sp_AjustarInventario'),
 ('sp_ListarClientes'),('sp_CrearCliente'),('sp_ActualizarCliente'),('sp_CotizarVenta'),
 ('sp_ProcesarVentaTransaccional'),('sp_ConsultarResultadoVenta'),('sp_ConsultarVentasPropias'),('sp_ConsultarFactura'),
 ('sp_ObtenerHistoricoVentas'),('sp_ObtenerResumenInicio'),('sp_ConsultarBitacoraAcceso'),
 ('sp_ConsultarAuditoriaDML'),('sp_ConsultarAuditoriaDDL'),('sp_ListarUsuarios'),('sp_CrearUsuario'),
 ('sp_ActualizarUsuario'),('sp_GenerarPasswordTemporal'),('sp_ListarRoles'),('sp_CrearRol'),('sp_ActualizarRol'),('sp_ListarPermisos');
INSERT @Faltantes SELECT 'PROCEDURE',Nombre FROM @Procedimientos WHERE OBJECT_ID(N'dbo.'+Nombre,N'P') IS NULL;

DECLARE @Funciones TABLE(Nombre sysname);
INSERT @Funciones VALUES
 ('fn_ContrasenaCumplePolitica'),('fn_TienePermiso'),('fn_CalcularSubtotal'),('fn_CalcularIVA'),
 ('fn_ConsultarAuditoriaDML'),('fn_ObtenerHistoricoVentas');
INSERT @Faltantes SELECT 'FUNCTION',Nombre FROM @Funciones WHERE OBJECT_ID(N'dbo.'+Nombre) IS NULL;

IF TYPE_ID(N'dbo.TVP_DetalleFactura') IS NULL INSERT @Faltantes VALUES('TYPE','TVP_DetalleFactura');
IF TYPE_ID(N'dbo.TVP_IdEntero') IS NULL INSERT @Faltantes VALUES('TYPE','TVP_IdEntero');
IF TYPE_ID(N'dbo.TVP_ListaEnteros') IS NULL INSERT @Faltantes VALUES('TYPE','TVP_ListaEnteros');
IF TYPE_ID(N'dbo.TVP_CodigosPermiso') IS NULL INSERT @Faltantes VALUES('TYPE','TVP_CodigosPermiso');
IF OBJECT_ID(N'dbo.SeqNumeroFactura',N'SO') IS NULL INSERT @Faltantes VALUES('SEQUENCE','SeqNumeroFactura');

DECLARE @Triggers TABLE(Nombre sysname,EsDDL bit);
INSERT @Triggers VALUES
 ('trg_Usuario_AuditoriaDML',0),('trg_Rol_AuditoriaDML',0),('trg_UsuarioRol_AuditoriaDML',0),
 ('trg_RolPermiso_AuditoriaDML',0),('trg_Producto_AuditoriaDML',0),('trg_Cliente_AuditoriaDML',0),
 ('trg_Factura_AuditoriaDML',0),('trg_DetalleFactura_AuditoriaDML',0),('trg_MovimientoCaja_AuditoriaDML',0),
 ('trg_PreferenciaUsuario_AuditoriaDML',0),('trg_SecureFinance_AuditoriaDDL',1);
INSERT @Faltantes
SELECT 'TRIGGER',t.Nombre FROM @Triggers t
WHERE (t.EsDDL=0 AND OBJECT_ID(N'dbo.'+t.Nombre,N'TR') IS NULL)
   OR (t.EsDDL=1 AND NOT EXISTS(SELECT 1 FROM sys.triggers st WHERE st.parent_class=0 AND st.name=t.Nombre));

IF EXISTS(SELECT 1 FROM @Faltantes)
BEGIN
    SELECT * FROM @Faltantes ORDER BY Tipo,Nombre;
    THROW 51006,N'El contrato SQL esta incompleto.',1;
END;

IF NOT EXISTS(SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId='0001_baseline')
   OR NOT EXISTS(SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId='0002_security_contract_hardening')
    THROW 51006,N'Faltan migraciones obligatorias registradas.',1;
IF DATABASE_PRINCIPAL_ID(N'SecureFinanceApiExecutor') IS NULL
    THROW 51006,N'No existe el rol SQL minimo de la API.',1;
IF EXISTS
(
    SELECT 1
    FROM (VALUES(N'TVP_DetalleFactura'),(N'TVP_ListaEnteros'),(N'TVP_CodigosPermiso')) expected(typeName)
    CROSS APPLY (SELECT TYPE_ID(N'dbo.'+expected.typeName) AS typeId) resolved
    WHERE NOT EXISTS
    (
        SELECT 1 FROM sys.database_permissions dp
        WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'SecureFinanceApiExecutor')
          AND dp.class=6 AND dp.major_id=resolved.typeId AND dp.permission_name='EXECUTE' AND dp.state IN('G','W')
    )
       OR NOT EXISTS
    (
        SELECT 1 FROM sys.database_permissions dp
        WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'SecureFinanceApiExecutor')
          AND dp.class=6 AND dp.major_id=resolved.typeId AND dp.permission_name='REFERENCES' AND dp.state IN('G','W')
    )
)
    THROW 51006,N'Faltan permisos EXECUTE/REFERENCES sobre TVP para la API.',1;

IF dbo.fn_CalcularSubtotal(1,0.05)<>0.05 OR dbo.fn_CalcularIVA(0.05)<>0.01
    THROW 51006,N'Fallo el caso decimal 0.05 -> 0.01.',1;
IF dbo.fn_CalcularSubtotal(1,100.00)<>100.00 OR dbo.fn_CalcularIVA(100.00)<>12.00
    THROW 51006,N'Fallo el caso 100.00 -> 12.00.',1;
SELECT 'ok' AS contractStatus,SYSUTCDATETIME() AS checkedAt;
GO
