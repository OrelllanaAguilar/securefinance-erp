:on error exit
USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF RIGHT(LOWER(DB_NAME()),5)<>N'_test'
    THROW 51006,N'La inyeccion de fallos solo se permite en una base cuyo nombre termine en _Test.',1;
IF COALESCE(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1 AND COALESCE(IS_ROLEMEMBER(N'db_owner'),0)<>1
    THROW 51002,N'La inyeccion de fallos requiere una conexion administrativa fuera del servicio.',1;

DECLARE @Marca varchar(20)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),20),
        @UsuarioId int,@RolId int,@PermisoId int,@ClienteId int,@ProductoId int,
        @SesionHash varbinary(64)=HASHBYTES('SHA2_512',CONVERT(varbinary(128),NEWID())),
        @Clave uniqueidentifier=NEWID(),@CorrelationId uniqueidentifier=NEWID(),@StockAntes int=1,
        @Trigger sysname;
SET @Trigger=CONVERT(sysname,N'tr_SecureFinanceTest_FacturaFault_'+@Marca);

BEGIN TRY
    /*
      Todo el escenario, incluido el trigger de fallo, vive en una transaccion
      externa. El procedimiento revierte esa transaccion completa al capturar el
      error del trigger, por lo que no quedan usuarios, roles ni catalogos de prueba.
    */
    BEGIN TRANSACTION;
    SELECT @PermisoId=PermisoId FROM dbo.Permiso WHERE Codigo='VENTAS_CREAR' AND Activo=1;
    IF @PermisoId IS NULL THROW 51006,N'No existe VENTAS_CREAR.',1;

    INSERT dbo.Rol(Nombre,Descripcion) VALUES('Fault'+@Marca,N'Rol efimero de prueba de rollback');
    SET @RolId=CONVERT(int,SCOPE_IDENTITY());
    INSERT dbo.Rol_Permiso(RolId,PermisoId) VALUES(@RolId,@PermisoId);

    DECLARE @Salt varbinary(32)=CRYPT_GEN_RANDOM(32);
    INSERT dbo.Usuario(NombreUsuario,NombreVisible,PasswordHash,PasswordSalt,DebeCambiarPassword,Activo)
    VALUES('fault.'+@Marca,N'Usuario efimero de rollback',HASHBYTES('SHA2_512',@Salt+0x0102),@Salt,0,1);
    SET @UsuarioId=CONVERT(int,SCOPE_IDENTITY());
    INSERT dbo.Usuario_Rol(UsuarioId,RolId,AsignadoPorUsuarioId) VALUES(@UsuarioId,@RolId,@UsuarioId);
    INSERT dbo.PreferenciaUsuario(UsuarioId,Tema) VALUES(@UsuarioId,'sistema');
    INSERT dbo.Sesion(SesionHash,UsuarioId,VersionSeguridad,MinutosInactividad,ExpiraInactividadUtc,ExpiraAbsolutaUtc)
    VALUES(@SesionHash,@UsuarioId,1,30,DATEADD(minute,30,SYSUTCDATETIME()),DATEADD(hour,8,SYSUTCDATETIME()));

    INSERT dbo.Cliente(Identificador,Nombre) VALUES('F-'+@Marca,N'Cliente efimero de rollback');
    SET @ClienteId=CONVERT(int,SCOPE_IDENTITY());
    INSERT dbo.Producto(Codigo,Descripcion,Unidad,Precio,Stock)
    VALUES('F-'+@Marca,N'Producto efimero de rollback','UNIDAD',100.00,@StockAntes);
    SET @ProductoId=CONVERT(int,SCOPE_IDENTITY());

    DECLARE @CrearTrigger nvarchar(max)=N'
        CREATE TRIGGER dbo.'+QUOTENAME(@Trigger)+N'
        ON dbo.Factura
        AFTER INSERT
        AS
        BEGIN
            SET NOCOUNT ON;
            IF RIGHT(LOWER(DB_NAME()),5)=N''_test''
               AND TRY_CONVERT(nvarchar(40),SESSION_CONTEXT(N''SecureFinanceTestFault''))=N''AFTER_INVOICE''
                THROW 52001,N''Fallo de prueba aislado despues del encabezado.'',1;
        END;
    ';
    EXEC sys.sp_executesql @CrearTrigger;

    DECLARE @Detalle dbo.TVP_DetalleFactura;
    INSERT @Detalle(ProductoId,Cantidad) VALUES(@ProductoId,1);
    EXEC sys.sp_set_session_context @key=N'SecureFinanceTestFault',@value=N'AFTER_INVOICE';

    BEGIN TRY
        EXEC dbo.sp_ProcesarVentaTransaccional
            @SesionHash=@SesionHash,@DireccionIP='127.0.0.1',@CorrelationId=@CorrelationId,
            @ClienteId=@ClienteId,@Detalle=@Detalle,@TotalAceptadoTexto='112.00',@ClaveIdempotencia=@Clave;
        THROW 51006,N'La venta no activo el fallo de prueba esperado.',1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER()<>52001 THROW;
    END CATCH;

    EXEC sys.sp_set_session_context @key=N'SecureFinanceTestFault',@value=NULL;

    IF XACT_STATE()<>0 OR @@TRANCOUNT<>0
        THROW 51006,N'El procedimiento no revirtio la transaccion externa completa.',1;
    IF OBJECT_ID(N'dbo.'+@Trigger,N'TR') IS NOT NULL
        THROW 51006,N'El trigger temporal sobrevivio al rollback.',1;
    IF EXISTS(SELECT 1 FROM dbo.Factura WHERE CorrelationId=@CorrelationId OR (UsuarioId=@UsuarioId AND ClaveIdempotencia=@Clave))
        THROW 51006,N'El rollback dejo un encabezado de factura.',1;
    IF EXISTS(SELECT 1 FROM dbo.Detalle_Factura d JOIN dbo.Factura f ON f.FacturaId=d.FacturaId WHERE f.CorrelationId=@CorrelationId)
        THROW 51006,N'El rollback dejo detalle de factura.',1;
    IF EXISTS(SELECT 1 FROM dbo.MovimientoCaja m JOIN dbo.Factura f ON f.FacturaId=m.FacturaId WHERE f.CorrelationId=@CorrelationId)
        THROW 51006,N'El rollback dejo un movimiento de caja.',1;
    IF EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones WHERE CorrelationId=@CorrelationId)
        THROW 51006,N'El rollback dejo auditoria DML de una operacion no confirmada.',1;
    IF EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoId)
       OR EXISTS(SELECT 1 FROM dbo.Cliente WHERE ClienteId=@ClienteId)
       OR EXISTS(SELECT 1 FROM dbo.Usuario WHERE UsuarioId=@UsuarioId)
       OR EXISTS(SELECT 1 FROM dbo.Rol WHERE RolId=@RolId)
        THROW 51006,N'La prueba dejo datos sinteticos persistentes.',1;
    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.Bitacora_Incidente
        WHERE Operacion='sp_ProcesarVentaTransaccional' AND CorrelationId=@CorrelationId AND NumeroError=52001
    )
        THROW 51006,N'No se registro el incidente separado despues del rollback.',1;

    DELETE dbo.Bitacora_Incidente
    WHERE Operacion='sp_ProcesarVentaTransaccional' AND CorrelationId=@CorrelationId AND NumeroError=52001;

    SELECT 'ok' AS rollbackAfterInvoice, @CorrelationId AS correlationId;
END TRY
BEGIN CATCH
    EXEC sys.sp_set_session_context @key=N'SecureFinanceTestFault',@value=NULL;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF OBJECT_ID(N'dbo.'+@Trigger,N'TR') IS NOT NULL
    BEGIN
        DECLARE @EliminarTrigger nvarchar(max)=N'DROP TRIGGER dbo.'+QUOTENAME(@Trigger)+N';';
        EXEC sys.sp_executesql @EliminarTrigger;
    END;
    DELETE dbo.Bitacora_Incidente
    WHERE Operacion='sp_ProcesarVentaTransaccional' AND CorrelationId=@CorrelationId AND NumeroError=52001;
    THROW;
END CATCH;
GO
