USE [$(DatabaseName)];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ListarUnidadesMedida
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int, @Usuario varchar(50), @Nombre nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,NULL,0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        IF dbo.fn_TienePermiso(@UsuarioId,'VENTAS_CREAR')=0
           AND dbo.fn_TienePermiso(@UsuarioId,'PRODUCTOS_GESTIONAR')=0
            THROW 51002,N'Permiso insuficiente para consultar productos.',1;
        SELECT Codigo AS code, Nombre AS name FROM dbo.UnidadMedida WHERE Activo=1 ORDER BY Nombre,Codigo;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ListarProductos
    @SesionHash varbinary(64), @DireccionIP varchar(45)=NULL, @CorrelationId uniqueidentifier=NULL,
    @Pagina int=1, @TamanoPagina tinyint=25, @Busqueda nvarchar(160)=NULL,
    @Orden varchar(40)='code', @Direccion varchar(4)='asc', @Estado varchar(8)='all'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc')
       OR @Estado NOT IN('all','active','inactive')
       OR @Orden NOT IN('code','description','price','stock','updatedAt')
        THROW 51006,N'Filtros o paginacion no validos.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,NULL,0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        IF dbo.fn_TienePermiso(@UsuarioId,'VENTAS_CREAR')=0
           AND dbo.fn_TienePermiso(@UsuarioId,'PRODUCTOS_GESTIONAR')=0
            THROW 51002,N'Permiso insuficiente para consultar productos.',1;

        SELECT @Total=COUNT_BIG(*) FROM dbo.Producto p
        WHERE (@Estado='all' OR (@Estado='active' AND p.Activo=1) OR (@Estado='inactive' AND p.Activo=0))
          AND (NULLIF(@Busqueda,N'') IS NULL OR p.Codigo LIKE N'%'+@Busqueda+N'%' OR p.Descripcion LIKE N'%'+@Busqueda+N'%');

        SELECT p.ProductoId AS id,p.Codigo AS code,p.Descripcion AS description,p.Unidad AS unit,
               CONVERT(varchar(40),CONVERT(decimal(19,2),p.Precio)) AS price,p.Stock AS stock,
               p.Activo AS active,p.CreadoUtc AS createdAt,p.ActualizadoUtc AS updatedAt,
               sys.fn_varbintohexstr(p.VersionFila) AS version
        FROM dbo.Producto p
        WHERE (@Estado='all' OR (@Estado='active' AND p.Activo=1) OR (@Estado='inactive' AND p.Activo=0))
          AND (NULLIF(@Busqueda,N'') IS NULL OR p.Codigo LIKE N'%'+@Busqueda+N'%' OR p.Descripcion LIKE N'%'+@Busqueda+N'%')
        ORDER BY
          CASE WHEN @Orden='code' AND @Direccion='asc' THEN p.Codigo END ASC,
          CASE WHEN @Orden='code' AND @Direccion='desc' THEN p.Codigo END DESC,
          CASE WHEN @Orden='description' AND @Direccion='asc' THEN p.Descripcion END ASC,
          CASE WHEN @Orden='description' AND @Direccion='desc' THEN p.Descripcion END DESC,
          CASE WHEN @Orden='price' AND @Direccion='asc' THEN p.Precio END ASC,
          CASE WHEN @Orden='price' AND @Direccion='desc' THEN p.Precio END DESC,
          CASE WHEN @Orden='stock' AND @Direccion='asc' THEN p.Stock END ASC,
          CASE WHEN @Orden='stock' AND @Direccion='desc' THEN p.Stock END DESC,
          CASE WHEN @Orden='updatedAt' AND @Direccion='asc' THEN p.ActualizadoUtc END ASC,
          CASE WHEN @Orden='updatedAt' AND @Direccion='desc' THEN p.ActualizadoUtc END DESC,
          p.ProductoId ASC
        OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,
               CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CrearProducto
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Codigo varchar(30),@Descripcion nvarchar(160),@Unidad varchar(20),@PrecioTexto varchar(40)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    DECLARE @PrecioAmplio decimal(38,6)=TRY_CONVERT(decimal(38,6),@PrecioTexto),@Precio decimal(19,2);
    IF LEN(LTRIM(RTRIM(@Codigo))) NOT BETWEEN 1 AND 30 OR LEN(LTRIM(RTRIM(@Descripcion))) NOT BETWEEN 2 AND 160
       OR @PrecioAmplio IS NULL OR @PrecioAmplio<>ROUND(@PrecioAmplio,2) OR @PrecioAmplio NOT BETWEEN 0.01 AND 999999.99
        THROW 51006,N'Datos de producto no validos.',1;
    SET @Precio=CONVERT(decimal(19,2),@PrecioAmplio);
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@ProductoId int;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'PRODUCTOS_GESTIONAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        IF NOT EXISTS(SELECT 1 FROM dbo.UnidadMedida WHERE Codigo=@Unidad AND Activo=1) THROW 51006,N'Unidad no valida.',1;
        INSERT dbo.Producto(Codigo,Descripcion,Unidad,Precio,Stock)
        VALUES(LTRIM(RTRIM(@Codigo)),LTRIM(RTRIM(@Descripcion)),@Unidad,@Precio,0);
        SET @ProductoId=CONVERT(int,SCOPE_IDENTITY());
        SELECT ProductoId AS id,Codigo AS code,Descripcion AS description,Unidad AS unit,
               CONVERT(varchar(40),Precio) AS price,Stock AS stock,Activo AS active,
               ActualizadoUtc AS updatedAt,sys.fn_varbintohexstr(VersionFila) AS version
        FROM dbo.Producto WHERE ProductoId=@ProductoId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        IF ERROR_NUMBER() IN(2601,2627) THROW 51004,N'Codigo de producto duplicado.',1;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ActualizarProducto
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @ProductoId int,@Codigo varchar(30)=NULL,@Descripcion nvarchar(160)=NULL,@Unidad varchar(20)=NULL,
    @PrecioTexto varchar(40)=NULL,@Activo bit=NULL,@Version binary(8)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    DECLARE @PrecioAmplio decimal(38,6)=TRY_CONVERT(decimal(38,6),@PrecioTexto),@Precio decimal(19,2)=NULL;
    IF @Codigo IS NOT NULL AND LEN(LTRIM(RTRIM(@Codigo))) NOT BETWEEN 1 AND 30 THROW 51006,N'Codigo no valido.',1;
    IF @Descripcion IS NOT NULL AND LEN(LTRIM(RTRIM(@Descripcion))) NOT BETWEEN 2 AND 160 THROW 51006,N'Descripcion no valida.',1;
    IF @PrecioTexto IS NOT NULL AND (@PrecioAmplio IS NULL OR @PrecioAmplio<>ROUND(@PrecioAmplio,2) OR @PrecioAmplio NOT BETWEEN 0.01 AND 999999.99)
        THROW 51006,N'Precio no valido.',1;
    IF @PrecioTexto IS NOT NULL SET @Precio=CONVERT(decimal(19,2),@PrecioAmplio);
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'PRODUCTOS_GESTIONAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        IF @Unidad IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.UnidadMedida WHERE Codigo=@Unidad AND Activo=1)
            THROW 51006,N'Unidad no valida.',1;
        UPDATE dbo.Producto SET Codigo=COALESCE(LTRIM(RTRIM(@Codigo)),Codigo),
            Descripcion=COALESCE(LTRIM(RTRIM(@Descripcion)),Descripcion),Unidad=COALESCE(@Unidad,Unidad),
            Precio=COALESCE(@Precio,Precio),Activo=COALESCE(@Activo,Activo),ActualizadoUtc=SYSUTCDATETIME()
        WHERE ProductoId=@ProductoId AND VersionFila=@Version;
        IF @@ROWCOUNT=0
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoId) THROW 51003,N'Producto inexistente.',1;
            THROW 51009,N'Version de producto obsoleta.',1;
        END;
        SELECT ProductoId AS id,Codigo AS code,Descripcion AS description,Unidad AS unit,
               CONVERT(varchar(40),Precio) AS price,Stock AS stock,Activo AS active,
               ActualizadoUtc AS updatedAt,sys.fn_varbintohexstr(VersionFila) AS version
        FROM dbo.Producto WHERE ProductoId=@ProductoId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        IF ERROR_NUMBER() IN(2601,2627) THROW 51004,N'Codigo de producto duplicado.',1;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AjustarInventario
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @ProductoId int,@Variacion int,@Motivo nvarchar(250),@Version binary(8)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Variacion=0 OR @Variacion NOT BETWEEN -999999 AND 999999 OR LEN(LTRIM(RTRIM(@Motivo))) NOT BETWEEN 10 AND 250
        THROW 51006,N'Ajuste de inventario no valido.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Anterior int,@Nuevo bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'PRODUCTOS_GESTIONAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        EXEC sys.sp_set_session_context @key=N'MotivoAuditoria',@value=@Motivo;
        BEGIN TRANSACTION;
        SELECT @Anterior=Stock FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK)
        WHERE ProductoId=@ProductoId AND VersionFila=@Version;
        IF @Anterior IS NULL
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoId) THROW 51003,N'Producto inexistente.',1;
            THROW 51009,N'Version de producto obsoleta.',1;
        END;
        SET @Nuevo=CONVERT(bigint,@Anterior)+@Variacion;
        IF @Nuevo NOT BETWEEN 0 AND 2147483647 THROW 51010,N'El ajuste deja existencias fuera de rango.',1;
        UPDATE dbo.Producto SET Stock=CONVERT(int,@Nuevo),ActualizadoUtc=SYSUTCDATETIME() WHERE ProductoId=@ProductoId;
        INSERT dbo.MovimientoInventario(ProductoId,Variacion,StockAnterior,StockNuevo,Motivo,UsuarioId,CorrelationId)
        VALUES(@ProductoId,@Variacion,@Anterior,CONVERT(int,@Nuevo),LTRIM(RTRIM(@Motivo)),@UsuarioId,@CorrelationId);
        COMMIT TRANSACTION;
        SELECT ProductoId AS id,Codigo AS code,Descripcion AS description,Unidad AS unit,
               CONVERT(varchar(40),Precio) AS price,Stock AS stock,Activo AS active,
               ActualizadoUtc AS updatedAt,sys.fn_varbintohexstr(VersionFila) AS version
        FROM dbo.Producto WHERE ProductoId=@ProductoId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria; THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ListarClientes
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Pagina int=1,@TamanoPagina tinyint=25,@Busqueda nvarchar(160)=NULL,
    @Orden varchar(40)='name',@Direccion varchar(4)='asc',@Estado varchar(8)='all'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc')
       OR @Estado NOT IN('all','active','inactive') OR @Orden NOT IN('identifier','name','email','updatedAt')
        THROW 51006,N'Filtros o paginacion no validos.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,NULL,0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        IF dbo.fn_TienePermiso(@UsuarioId,'VENTAS_CREAR')=0 AND dbo.fn_TienePermiso(@UsuarioId,'CLIENTES_GESTIONAR')=0
            THROW 51002,N'Permiso insuficiente para consultar clientes.',1;
        SELECT @Total=COUNT_BIG(*) FROM dbo.Cliente c
        WHERE (@Estado='all' OR (@Estado='active' AND c.Activo=1) OR (@Estado='inactive' AND c.Activo=0))
          AND (NULLIF(@Busqueda,N'') IS NULL OR c.Identificador LIKE N'%'+@Busqueda+N'%' OR c.Nombre LIKE N'%'+@Busqueda+N'%'
               OR c.Correo LIKE N'%'+@Busqueda+N'%' OR c.Telefono LIKE N'%'+@Busqueda+N'%');
        SELECT c.ClienteId AS id,c.Identificador AS identifier,c.Nombre AS name,c.Correo AS email,c.Telefono AS phone,
               c.Activo AS active,c.CreadoUtc AS createdAt,c.ActualizadoUtc AS updatedAt,sys.fn_varbintohexstr(c.VersionFila) AS version
        FROM dbo.Cliente c
        WHERE (@Estado='all' OR (@Estado='active' AND c.Activo=1) OR (@Estado='inactive' AND c.Activo=0))
          AND (NULLIF(@Busqueda,N'') IS NULL OR c.Identificador LIKE N'%'+@Busqueda+N'%' OR c.Nombre LIKE N'%'+@Busqueda+N'%'
               OR c.Correo LIKE N'%'+@Busqueda+N'%' OR c.Telefono LIKE N'%'+@Busqueda+N'%')
        ORDER BY
          CASE WHEN @Orden='identifier' AND @Direccion='asc' THEN c.Identificador END ASC,
          CASE WHEN @Orden='identifier' AND @Direccion='desc' THEN c.Identificador END DESC,
          CASE WHEN @Orden='name' AND @Direccion='asc' THEN c.Nombre END ASC,
          CASE WHEN @Orden='name' AND @Direccion='desc' THEN c.Nombre END DESC,
          CASE WHEN @Orden='email' AND @Direccion='asc' THEN c.Correo END ASC,
          CASE WHEN @Orden='email' AND @Direccion='desc' THEN c.Correo END DESC,
          CASE WHEN @Orden='updatedAt' AND @Direccion='asc' THEN c.ActualizadoUtc END ASC,
          CASE WHEN @Orden='updatedAt' AND @Direccion='desc' THEN c.ActualizadoUtc END DESC,c.ClienteId ASC
        OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CrearCliente
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Identificador varchar(30),@Nombre nvarchar(120),@Correo nvarchar(254)=NULL,@Telefono nvarchar(30)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF LEN(LTRIM(RTRIM(@Identificador))) NOT BETWEEN 1 AND 30 OR LEN(LTRIM(RTRIM(@Nombre))) NOT BETWEEN 2 AND 120
       OR LEN(COALESCE(@Correo,N''))>254 OR LEN(COALESCE(@Telefono,N''))>30
        THROW 51006,N'Datos de cliente no validos.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@ActorNombre nvarchar(120),@ClienteId int;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'CLIENTES_GESTIONAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@ActorNombre OUTPUT;
        INSERT dbo.Cliente(Identificador,Nombre,Correo,Telefono)
        VALUES(LTRIM(RTRIM(@Identificador)),LTRIM(RTRIM(@Nombre)),NULLIF(LTRIM(RTRIM(@Correo)),N''),NULLIF(LTRIM(RTRIM(@Telefono)),N''));
        SET @ClienteId=CONVERT(int,SCOPE_IDENTITY());
        SELECT ClienteId AS id,Identificador AS identifier,Nombre AS name,Correo AS email,Telefono AS phone,
               Activo AS active,ActualizadoUtc AS updatedAt,sys.fn_varbintohexstr(VersionFila) AS version
        FROM dbo.Cliente WHERE ClienteId=@ClienteId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        IF ERROR_NUMBER() IN(2601,2627) THROW 51004,N'Identificador de cliente duplicado.',1;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ActualizarCliente
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @ClienteId int,@Identificador varchar(30)=NULL,@Nombre nvarchar(120)=NULL,@Correo nvarchar(254)=NULL,
    @Telefono nvarchar(30)=NULL,@CambiarCorreo bit=0,@CambiarTelefono bit=0,@Activo bit=NULL,@Version binary(8)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Identificador IS NOT NULL AND LEN(LTRIM(RTRIM(@Identificador))) NOT BETWEEN 1 AND 30 THROW 51006,N'Identificador no valido.',1;
    IF @Nombre IS NOT NULL AND LEN(LTRIM(RTRIM(@Nombre))) NOT BETWEEN 2 AND 120 THROW 51006,N'Nombre no valido.',1;
    IF LEN(COALESCE(@Correo,N''))>254 OR LEN(COALESCE(@Telefono,N''))>30 THROW 51006,N'Contacto no valido.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@ActorNombre nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'CLIENTES_GESTIONAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@ActorNombre OUTPUT;
        UPDATE dbo.Cliente SET Identificador=COALESCE(LTRIM(RTRIM(@Identificador)),Identificador),
            Nombre=COALESCE(LTRIM(RTRIM(@Nombre)),Nombre),
            Correo=CASE WHEN @CambiarCorreo=1 THEN NULLIF(LTRIM(RTRIM(@Correo)),N'') ELSE Correo END,
            Telefono=CASE WHEN @CambiarTelefono=1 THEN NULLIF(LTRIM(RTRIM(@Telefono)),N'') ELSE Telefono END,
            Activo=COALESCE(@Activo,Activo),ActualizadoUtc=SYSUTCDATETIME()
        WHERE ClienteId=@ClienteId AND VersionFila=@Version;
        IF @@ROWCOUNT=0
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM dbo.Cliente WHERE ClienteId=@ClienteId) THROW 51003,N'Cliente inexistente.',1;
            THROW 51009,N'Version de cliente obsoleta.',1;
        END;
        SELECT ClienteId AS id,Identificador AS identifier,Nombre AS name,Correo AS email,Telefono AS phone,
               Activo AS active,ActualizadoUtc AS updatedAt,sys.fn_varbintohexstr(VersionFila) AS version
        FROM dbo.Cliente WHERE ClienteId=@ClienteId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        IF ERROR_NUMBER() IN(2601,2627) THROW 51004,N'Identificador de cliente duplicado.',1;
        THROW;
    END CATCH;
END;
GO
