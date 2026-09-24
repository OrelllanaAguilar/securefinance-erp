:on error exit
USE [master];
GO

DECLARE @DatabaseNameInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(DatabaseName))';
IF LEN(@DatabaseNameInput) NOT BETWEEN 1 AND 128
   OR @DatabaseNameInput LIKE N'%[^A-Za-z0-9_]%' COLLATE Latin1_General_100_BIN2
    THROW 51006,N'DatabaseName no es valido.',1;
IF DB_ID(@DatabaseNameInput) IS NULL
    THROW 51003,N'La base indicada no existe.',1;
GO

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF RIGHT(LOWER(DB_NAME()),5)<>N'_test'
    THROW 51006,N'La semilla demo solo puede aplicarse a una base cuyo nombre termine en _Test.',1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @ActorId int=(SELECT TOP(1) u.UsuarioId FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId
      JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE u.Activo=1 AND r.Activo=1 AND r.EsAdministrador=1 ORDER BY u.UsuarioId);
    IF @ActorId IS NULL THROW 51006,N'Primero debe aprovisionarse el administrador bootstrap.',1;
    DECLARE @Actor varchar(50)=(SELECT NombreUsuario FROM dbo.Usuario WHERE UsuarioId=@ActorId);
    EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=@ActorId;
    EXEC sys.sp_set_session_context @key=N'UsuarioAplicacion',@value=@Actor;
    EXEC sys.sp_set_session_context @key=N'MotivoAuditoria',@value=N'Carga inicial de datos demo';

    DECLARE @CajeroRolId int,@AuditorRolId int;
    SELECT @CajeroRolId=RolId FROM dbo.Rol WHERE Nombre='Cajero';
    IF @CajeroRolId IS NULL
    BEGIN
        INSERT dbo.Rol(Nombre,Descripcion) VALUES('Cajero',N'Procesamiento de ventas y consulta de comprobantes propios');
        SET @CajeroRolId=CONVERT(int,SCOPE_IDENTITY());
    END;
    ELSE
        UPDATE dbo.Rol SET Activo=1,ActualizadoUtc=SYSUTCDATETIME() WHERE RolId=@CajeroRolId AND Activo=0;
    SELECT @AuditorRolId=RolId FROM dbo.Rol WHERE Nombre='Auditor';
    IF @AuditorRolId IS NULL
    BEGIN
        INSERT dbo.Rol(Nombre,Descripcion) VALUES('Auditor',N'Consulta de reportes y auditoria');
        SET @AuditorRolId=CONVERT(int,SCOPE_IDENTITY());
    END;
    ELSE
        UPDATE dbo.Rol SET Activo=1,ActualizadoUtc=SYSUTCDATETIME() WHERE RolId=@AuditorRolId AND Activo=0;
    INSERT dbo.Rol_Permiso(RolId,PermisoId)
    SELECT @CajeroRolId,p.PermisoId FROM dbo.Permiso p WHERE p.Codigo='VENTAS_CREAR'
      AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@CajeroRolId AND rp.PermisoId=p.PermisoId);
    INSERT dbo.Rol_Permiso(RolId,PermisoId)
    SELECT @AuditorRolId,p.PermisoId FROM dbo.Permiso p WHERE p.Codigo IN('AUDITORIA_LEER','REPORTES_LEER')
      AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@AuditorRolId AND rp.PermisoId=p.PermisoId);

    IF NOT EXISTS(SELECT 1 FROM dbo.Cliente WHERE Identificador='CF-DEMO')
        INSERT dbo.Cliente(Identificador,Nombre,Correo,Telefono) VALUES('CF-DEMO',N'Consumidor Final Demo',N'demo@example.test',N'0000-0000');
    IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE Codigo='DEMO-001')
        INSERT dbo.Producto(Codigo,Descripcion,Unidad,Precio,Stock) VALUES('DEMO-001',N'Producto demostrativo A','UNIDAD',100.00,0);
    IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE Codigo='DEMO-002')
        INSERT dbo.Producto(Codigo,Descripcion,Unidad,Precio,Stock) VALUES('DEMO-002',N'Producto demostrativo decimal','UNIDAD',0.05,0);

    DECLARE @ProductoId int,@Stock int;
    DECLARE ProductosDemo CURSOR LOCAL FAST_FORWARD FOR
      SELECT ProductoId,CASE Codigo WHEN 'DEMO-001' THEN 50 ELSE 100 END FROM dbo.Producto WHERE Codigo IN('DEMO-001','DEMO-002') AND Stock=0;
    OPEN ProductosDemo; FETCH NEXT FROM ProductosDemo INTO @ProductoId,@Stock;
    WHILE @@FETCH_STATUS=0
    BEGIN
        UPDATE dbo.Producto SET Stock=@Stock,ActualizadoUtc=SYSUTCDATETIME() WHERE ProductoId=@ProductoId;
        INSERT dbo.MovimientoInventario(ProductoId,Variacion,StockAnterior,StockNuevo,Motivo,UsuarioId)
        VALUES(@ProductoId,@Stock,0,@Stock,N'Carga inicial de datos demo',@ActorId);
        FETCH NEXT FROM ProductosDemo INTO @ProductoId,@Stock;
    END;
    CLOSE ProductosDemo; DEALLOCATE ProductosDemo;
    COMMIT TRANSACTION;
    EXEC dbo.sp_LimpiarContextoAuditoria;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local','ProductosDemo')>=0 CLOSE ProductosDemo;
    IF CURSOR_STATUS('local','ProductosDemo')>-3 DEALLOCATE ProductosDemo;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    THROW;
END CATCH;
GO
