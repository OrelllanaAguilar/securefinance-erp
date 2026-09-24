USE [$(DatabaseName)];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CotizarVenta
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @ClienteId int,@Detalle dbo.TVP_DetalleFactura READONLY
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF NOT EXISTS(SELECT 1 FROM @Detalle) OR (SELECT COUNT(*) FROM @Detalle)>100
        THROW 51006,N'La venta debe contener entre 1 y 100 productos.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Tasa decimal(9,6),@Moneda char(3);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'VENTAS_CREAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        IF NOT EXISTS(SELECT 1 FROM dbo.Cliente WHERE ClienteId=@ClienteId AND Activo=1)
            THROW 51003,N'Cliente inexistente o inactivo.',1;
        SELECT @Tasa=TasaIVA,@Moneda=MonedaCodigo FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1;
        IF @Tasa IS NULL OR @Moneda IS NULL THROW 51006,N'Configuracion comercial incompleta.',1;
        IF EXISTS
        (
            SELECT 1 FROM @Detalle d LEFT JOIN dbo.Producto p ON p.ProductoId=d.ProductoId AND p.Activo=1
            WHERE p.ProductoId IS NULL
        ) THROW 51004,N'Uno o mas productos no estan disponibles.',1;
        IF EXISTS
        (
            SELECT 1 FROM @Detalle d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId
            WHERE p.Stock<d.Cantidad
        ) THROW 51010,N'Existencias insuficientes.',1;

        SELECT p.ProductoId AS productId,p.Codigo AS code,p.Descripcion AS description,p.Unidad AS unit,
               d.Cantidad AS quantity,CONVERT(varchar(40),p.Precio) AS unitPrice,
               CONVERT(varchar(40),dbo.fn_CalcularSubtotal(d.Cantidad,p.Precio)) AS lineTotal,p.Stock AS stock
        FROM @Detalle d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId
        ORDER BY p.Descripcion,p.ProductoId;

        DECLARE @Subtotal decimal(19,2)=
            (SELECT SUM(dbo.fn_CalcularSubtotal(d.Cantidad,p.Precio)) FROM @Detalle d JOIN dbo.Producto p ON p.ProductoId=d.ProductoId);
        DECLARE @IVA decimal(19,2)=CONVERT(decimal(19,2),ROUND(@Subtotal*@Tasa,2));
        SELECT CONVERT(varchar(40),@Subtotal) AS subtotal,
               CONVERT(varchar(20),CONVERT(decimal(9,2),@Tasa*100)) AS taxRate,
               CONVERT(varchar(40),@IVA) AS tax,CONVERT(varchar(40),@Subtotal+@IVA) AS total,@Moneda AS currency;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaTransaccional
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @ClienteId int,@Detalle dbo.TVP_DetalleFactura READONLY,@TotalAceptadoTexto varchar(40),
    @ClaveIdempotencia uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF NOT EXISTS(SELECT 1 FROM @Detalle) OR (SELECT COUNT(*) FROM @Detalle)>100
        THROW 51006,N'La venta debe contener entre 1 y 100 productos.',1;
    DECLARE @TotalAmplio decimal(38,6)=TRY_CONVERT(decimal(38,6),@TotalAceptadoTexto),@TotalAceptado decimal(19,2);
    IF @TotalAmplio IS NULL OR @TotalAmplio<>ROUND(@TotalAmplio,2) OR @TotalAmplio<=0 OR @TotalAmplio>99999999999999999.99
        THROW 51006,N'Total aceptado no valido.',1;
    SET @TotalAceptado=CONVERT(decimal(19,2),@TotalAmplio);

    DECLARE @UsuarioId int,@Usuario varchar(50),@CajeroNombre nvarchar(120),@FacturaId bigint,
            @Subtotal decimal(19,2),@IVA decimal(19,2),@Total decimal(19,2),@Tasa decimal(9,6),@Moneda char(3),
            @ClienteIdentificador varchar(30),@ClienteNombre nvarchar(120),@Replayed bit=0,
            @CadenaLineas nvarchar(max),@Huella varbinary(32),@Bloqueo int;
    DECLARE @TotalCanonico varchar(40)=CONVERT(varchar(40),@TotalAceptado);
    SELECT @CadenaLineas=STRING_AGG(CONVERT(nvarchar(max),CONCAT(d.ProductoId,N':',d.Cantidad)),N';')
           WITHIN GROUP(ORDER BY d.ProductoId) FROM @Detalle d;
    SET @Huella=HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONCAT(@ClienteId,N'|',@TotalCanonico,N'|',@CadenaLineas)));

    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'VENTAS_CREAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@CajeroNombre OUTPUT;
        BEGIN TRANSACTION;
        DECLARE @RecursoBloqueo nvarchar(255) =
            CONCAT(N'SecureFinanceERP:Venta:',@UsuarioId,N':',CONVERT(nvarchar(36),@ClaveIdempotencia));
        EXEC @Bloqueo=sys.sp_getapplock
            @Resource=@RecursoBloqueo,
            @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
        IF @Bloqueo<0 THROW 51004,N'No fue posible serializar la solicitud de venta.',1;

        SELECT @FacturaId=FacturaId FROM dbo.Factura WITH(UPDLOCK,HOLDLOCK)
        WHERE UsuarioId=@UsuarioId AND ClaveIdempotencia=@ClaveIdempotencia;
        IF @FacturaId IS NOT NULL
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@FacturaId AND HuellaContenido=@Huella)
                THROW 51008,N'Clave de idempotencia reutilizada con contenido distinto.',1;
            SET @Replayed=1;
            COMMIT TRANSACTION;
            SELECT f.FacturaId AS invoiceId,f.Numero AS number,f.Estado AS status,f.ClienteId AS customerId,
                   f.ClienteIdentificador AS customerIdentifier,f.ClienteNombre AS customerName,
                   f.UsuarioId AS cashierId,f.CajeroNombre AS cashierName,f.FechaUtc AS issuedAt,f.Moneda AS currency,
                   CONVERT(varchar(20),CONVERT(decimal(9,2),f.TasaIVA*100)) AS taxRate,CONVERT(varchar(40),f.Subtotal) AS subtotal,
                   CONVERT(varchar(40),f.IVA) AS tax,CONVERT(varchar(40),f.Total) AS total,
                   f.ClaveIdempotencia AS idempotencyKey,CONVERT(bit,1) AS replayed
            FROM dbo.Factura f WHERE f.FacturaId=@FacturaId;
            EXEC dbo.sp_LimpiarContextoAuditoria;
            RETURN;
        END;

        SELECT @ClienteIdentificador=Identificador,@ClienteNombre=Nombre
        FROM dbo.Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId AND Activo=1;
        IF @ClienteIdentificador IS NULL THROW 51003,N'Cliente inexistente o inactivo.',1;
        SELECT @Tasa=TasaIVA,@Moneda=MonedaCodigo FROM dbo.ConfiguracionSistema WITH(HOLDLOCK) WHERE ConfiguracionId=1;
        IF @Tasa IS NULL OR @Moneda IS NULL THROW 51006,N'Configuracion comercial incompleta.',1;

        CREATE TABLE #Lineas
        (
            ProductoId int NOT NULL PRIMARY KEY,Codigo varchar(30) NOT NULL,Descripcion nvarchar(160) NOT NULL,
            Unidad varchar(20) NOT NULL,Cantidad int NOT NULL,Precio decimal(19,2) NOT NULL,Importe decimal(19,2) NOT NULL,Stock int NOT NULL
        );
        DECLARE @ProductoId int,@Cantidad int,@Codigo varchar(30),@Descripcion nvarchar(160),@Unidad varchar(20),@Precio decimal(19,2),@Stock int,@Activo bit;
        DECLARE ProductosVenta CURSOR LOCAL FAST_FORWARD FOR SELECT ProductoId,Cantidad FROM @Detalle ORDER BY ProductoId;
        OPEN ProductosVenta;
        FETCH NEXT FROM ProductosVenta INTO @ProductoId,@Cantidad;
        WHILE @@FETCH_STATUS=0
        BEGIN
            SELECT @Codigo=NULL,@Descripcion=NULL,@Unidad=NULL,@Precio=NULL,@Stock=NULL,@Activo=NULL;
            SELECT @Codigo=Codigo,@Descripcion=Descripcion,@Unidad=Unidad,@Precio=Precio,@Stock=Stock,@Activo=Activo
            FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=@ProductoId;
            IF @Codigo IS NULL OR @Activo=0 THROW 51004,N'Producto inexistente o inactivo.',1;
            IF @Stock<@Cantidad THROW 51010,N'Existencias insuficientes.',1;
            INSERT #Lineas VALUES(@ProductoId,@Codigo,@Descripcion,@Unidad,@Cantidad,@Precio,dbo.fn_CalcularSubtotal(@Cantidad,@Precio),@Stock);
            FETCH NEXT FROM ProductosVenta INTO @ProductoId,@Cantidad;
        END;
        CLOSE ProductosVenta; DEALLOCATE ProductosVenta;

        SELECT @Subtotal=SUM(Importe) FROM #Lineas;
        SET @IVA=CONVERT(decimal(19,2),ROUND(@Subtotal*@Tasa,2)); SET @Total=@Subtotal+@IVA;
        IF @Total<>@TotalAceptado THROW 51004,N'La cotizacion cambio; confirme el nuevo total.',1;

        UPDATE p SET Stock=p.Stock-l.Cantidad,ActualizadoUtc=SYSUTCDATETIME()
        FROM dbo.Producto p JOIN #Lineas l ON l.ProductoId=p.ProductoId
        WHERE p.Stock>=l.Cantidad;
        IF @@ROWCOUNT<>(SELECT COUNT(*) FROM #Lineas) THROW 51010,N'Existencias insuficientes.',1;

        INSERT dbo.Factura
        (ClienteId,ClienteIdentificador,ClienteNombre,UsuarioId,CajeroNombre,Moneda,TasaIVA,Subtotal,IVA,Total,ClaveIdempotencia,HuellaContenido,CorrelationId)
        VALUES(@ClienteId,@ClienteIdentificador,@ClienteNombre,@UsuarioId,@CajeroNombre,@Moneda,@Tasa,@Subtotal,@IVA,@Total,@ClaveIdempotencia,@Huella,@CorrelationId);
        SET @FacturaId=CONVERT(bigint,SCOPE_IDENTITY());

        INSERT dbo.Detalle_Factura(FacturaId,ProductoId,ProductoCodigo,ProductoDescripcion,Unidad,Cantidad,PrecioUnitario,Importe)
        SELECT @FacturaId,ProductoId,Codigo,Descripcion,Unidad,Cantidad,Precio,Importe FROM #Lineas;
        INSERT dbo.MovimientoCaja(FacturaId,Importe,Moneda,UsuarioId) VALUES(@FacturaId,@Total,@Moneda,@UsuarioId);
        COMMIT TRANSACTION;

        SELECT f.FacturaId AS invoiceId,f.Numero AS number,f.Estado AS status,f.ClienteId AS customerId,
               f.ClienteIdentificador AS customerIdentifier,f.ClienteNombre AS customerName,
               f.UsuarioId AS cashierId,f.CajeroNombre AS cashierName,f.FechaUtc AS issuedAt,f.Moneda AS currency,
               CONVERT(varchar(20),CONVERT(decimal(9,2),f.TasaIVA*100)) AS taxRate,CONVERT(varchar(40),f.Subtotal) AS subtotal,
               CONVERT(varchar(40),f.IVA) AS tax,CONVERT(varchar(40),f.Total) AS total,
               f.ClaveIdempotencia AS idempotencyKey,CONVERT(bit,0) AS replayed
        FROM dbo.Factura f WHERE f.FacturaId=@FacturaId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorNumero int=ERROR_NUMBER(),@ErrorMensaje nvarchar(500)=LEFT(ERROR_MESSAGE(),500);
        IF CURSOR_STATUS('local','ProductosVenta')>=0 CLOSE ProductosVenta;
        IF CURSOR_STATUS('local','ProductosVenta')>-3 DEALLOCATE ProductosVenta;
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        IF @ErrorNumero NOT BETWEEN 51001 AND 51012
            INSERT dbo.Bitacora_Incidente(Operacion,UsuarioId,CorrelationId,NumeroError,MensajeSanitizado)
            VALUES('sp_ProcesarVentaTransaccional',@UsuarioId,@CorrelationId,@ErrorNumero,@ErrorMensaje);
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarResultadoVenta
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @ClaveIdempotencia uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'VENTAS_CREAR',0,1,
            @UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        SELECT f.FacturaId AS invoiceId,f.Numero AS number,f.Estado AS status,f.ClienteId AS customerId,
               f.ClienteNombre AS customerName,f.FechaUtc AS issuedAt,f.Moneda AS currency,
               CONVERT(varchar(40),f.Subtotal) AS subtotal,CONVERT(varchar(40),f.IVA) AS tax,
               CONVERT(varchar(40),f.Total) AS total,f.ClaveIdempotencia AS idempotencyKey,CONVERT(bit,1) AS replayed
        FROM dbo.Factura f WHERE f.UsuarioId=@UsuarioId AND f.ClaveIdempotencia=@ClaveIdempotencia;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarVentasPropias
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Pagina int=1,@TamanoPagina tinyint=25,@Busqueda nvarchar(160)=NULL,@Orden varchar(40)='date',@Direccion varchar(4)='desc',
    @FechaDesde varchar(10)=NULL,@FechaHasta varchar(10)=NULL,@Alcance varchar(4)='mine'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc')
       OR @Orden NOT IN('date','number','customer','total') OR @Alcance NOT IN('mine','all')
        THROW 51006,N'Filtros o paginacion no validos.',1;
    DECLARE @Desde date=TRY_CONVERT(date,@FechaDesde,23),@Hasta date=TRY_CONVERT(date,@FechaHasta,23);
    IF (@FechaDesde IS NOT NULL AND @Desde IS NULL) OR (@FechaHasta IS NOT NULL AND @Hasta IS NULL)
       OR (@Desde IS NOT NULL AND @Hasta IS NOT NULL AND (@Desde>@Hasta OR DATEDIFF(day,@Desde,@Hasta)>365))
        THROW 51006,N'Rango de fechas no valido.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Zona sysname,@DesdeUtc datetime2(3),@HastaUtc datetime2(3),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,NULL,0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        IF @Alcance='all' AND dbo.fn_TienePermiso(@UsuarioId,'REPORTES_LEER')=0 THROW 51002,N'Reportes no autorizados.',1;
        IF @Alcance='mine' AND dbo.fn_TienePermiso(@UsuarioId,'VENTAS_CREAR')=0 THROW 51002,N'Ventas propias no autorizadas.',1;
        SELECT @Zona=ZonaHorariaSql FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1;
        IF @Desde IS NOT NULL SET @DesdeUtc=CONVERT(datetime2(3),(CONVERT(datetime2(0),@Desde) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        IF @Hasta IS NOT NULL SET @HastaUtc=CONVERT(datetime2(3),(DATEADD(day,1,CONVERT(datetime2(0),@Hasta)) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        SELECT @Total=COUNT_BIG(*) FROM dbo.Factura f
        WHERE (@Alcance='all' OR f.UsuarioId=@UsuarioId) AND (@DesdeUtc IS NULL OR f.FechaUtc>=@DesdeUtc) AND (@HastaUtc IS NULL OR f.FechaUtc<@HastaUtc)
          AND (NULLIF(@Busqueda,N'') IS NULL OR CONVERT(nvarchar(30),f.Numero) LIKE N'%'+@Busqueda+N'%' OR f.ClienteNombre LIKE N'%'+@Busqueda+N'%');
        SELECT f.FacturaId AS id,f.Numero AS number,f.FechaUtc AS issuedAt,f.Estado AS status,
               f.ClienteNombre AS customerName,f.CajeroNombre AS cashierName,f.Moneda AS currency,
               CONVERT(varchar(40),f.Subtotal) AS subtotal,CONVERT(varchar(40),f.IVA) AS tax,CONVERT(varchar(40),f.Total) AS total
        FROM dbo.Factura f
        WHERE (@Alcance='all' OR f.UsuarioId=@UsuarioId) AND (@DesdeUtc IS NULL OR f.FechaUtc>=@DesdeUtc) AND (@HastaUtc IS NULL OR f.FechaUtc<@HastaUtc)
          AND (NULLIF(@Busqueda,N'') IS NULL OR CONVERT(nvarchar(30),f.Numero) LIKE N'%'+@Busqueda+N'%' OR f.ClienteNombre LIKE N'%'+@Busqueda+N'%')
        ORDER BY CASE WHEN @Orden='date' AND @Direccion='asc' THEN f.FechaUtc END ASC,CASE WHEN @Orden='date' AND @Direccion='desc' THEN f.FechaUtc END DESC,
          CASE WHEN @Orden='number' AND @Direccion='asc' THEN f.Numero END ASC,CASE WHEN @Orden='number' AND @Direccion='desc' THEN f.Numero END DESC,
          CASE WHEN @Orden='customer' AND @Direccion='asc' THEN f.ClienteNombre END ASC,CASE WHEN @Orden='customer' AND @Direccion='desc' THEN f.ClienteNombre END DESC,
          CASE WHEN @Orden='total' AND @Direccion='asc' THEN f.Total END ASC,CASE WHEN @Orden='total' AND @Direccion='desc' THEN f.Total END DESC,
          f.FacturaId DESC OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarFactura
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,@FacturaId bigint
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Propietario int;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,NULL,0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        SELECT @Propietario=UsuarioId FROM dbo.Factura WHERE FacturaId=@FacturaId;
        IF @Propietario IS NULL THROW 51003,N'Factura inexistente.',1;
        IF dbo.fn_TienePermiso(@UsuarioId,'REPORTES_LEER')=0
           AND NOT(@Propietario=@UsuarioId AND dbo.fn_TienePermiso(@UsuarioId,'VENTAS_CREAR')=1)
            THROW 51003,N'Factura fuera del alcance autorizado.',1;
        SELECT f.FacturaId AS id,f.Numero AS number,f.Estado AS status,f.FechaUtc AS issuedAt,
               f.ClienteId AS customerId,f.ClienteIdentificador AS customerIdentifier,f.ClienteNombre AS customerName,
               f.UsuarioId AS cashierId,f.CajeroNombre AS cashierName,f.Moneda AS currency,
               CONVERT(varchar(20),CONVERT(decimal(9,2),f.TasaIVA*100)) AS taxRate,
               CONVERT(varchar(40),f.Subtotal) AS subtotal,CONVERT(varchar(40),f.IVA) AS tax,CONVERT(varchar(40),f.Total) AS total
        FROM dbo.Factura f WHERE f.FacturaId=@FacturaId;
        SELECT d.DetalleFacturaId AS id,d.ProductoId AS productId,d.ProductoCodigo AS code,d.ProductoDescripcion AS description,
               d.Unidad AS unit,d.Cantidad AS quantity,CONVERT(varchar(40),d.PrecioUnitario) AS unitPrice,CONVERT(varchar(40),d.Importe) AS lineTotal
        FROM dbo.Detalle_Factura d WHERE d.FacturaId=@FacturaId ORDER BY d.DetalleFacturaId;
        SELECT m.MovimientoCajaId AS id,m.Tipo AS type,CONVERT(varchar(40),m.Importe) AS amount,m.Moneda AS currency,m.FechaUtc AS occurredAt
        FROM dbo.MovimientoCaja m WHERE m.FacturaId=@FacturaId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ObtenerHistoricoVentas
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @FechaDesde varchar(10),@FechaHasta varchar(10),@Pagina int=1,@TamanoPagina tinyint=25,
    @Busqueda nvarchar(160)=NULL,@Orden varchar(40)='date',@Direccion varchar(4)='desc'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    DECLARE @Desde date=TRY_CONVERT(date,@FechaDesde,23),@Hasta date=TRY_CONVERT(date,@FechaHasta,23);
    IF @Desde IS NULL OR @Hasta IS NULL OR @Desde>@Hasta OR DATEDIFF(day,@Desde,@Hasta)>365
       OR @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc')
       OR @Orden NOT IN('date','number','customer','cashier','total') THROW 51006,N'Filtros de reporte no validos.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Zona sysname,@DesdeUtc datetime2(3),@HastaUtc datetime2(3),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'REPORTES_LEER',0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        SELECT @Zona=ZonaHorariaSql FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1;
        SET @DesdeUtc=CONVERT(datetime2(3),(CONVERT(datetime2(0),@Desde) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        SET @HastaUtc=CONVERT(datetime2(3),(DATEADD(day,1,CONVERT(datetime2(0),@Hasta)) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        SELECT @Total=COUNT_BIG(*) FROM dbo.fn_ObtenerHistoricoVentas(@DesdeUtc,@HastaUtc) v
        WHERE NULLIF(@Busqueda,N'') IS NULL OR CONVERT(nvarchar(30),v.Numero) LIKE N'%'+@Busqueda+N'%'
           OR v.ClienteNombre LIKE N'%'+@Busqueda+N'%' OR v.CajeroNombre LIKE N'%'+@Busqueda+N'%';
        SELECT v.FacturaId AS id,v.Numero AS number,v.FechaUtc AS issuedAt,v.ClienteNombre AS customerName,
               v.CajeroNombre AS cashierName,v.Moneda AS currency,CONVERT(varchar(40),v.Subtotal) AS subtotal,
               CONVERT(varchar(40),v.IVA) AS tax,CONVERT(varchar(40),v.Total) AS total
        FROM dbo.fn_ObtenerHistoricoVentas(@DesdeUtc,@HastaUtc) v
        WHERE NULLIF(@Busqueda,N'') IS NULL OR CONVERT(nvarchar(30),v.Numero) LIKE N'%'+@Busqueda+N'%'
           OR v.ClienteNombre LIKE N'%'+@Busqueda+N'%' OR v.CajeroNombre LIKE N'%'+@Busqueda+N'%'
        ORDER BY CASE WHEN @Orden='date' AND @Direccion='asc' THEN v.FechaUtc END ASC,CASE WHEN @Orden='date' AND @Direccion='desc' THEN v.FechaUtc END DESC,
          CASE WHEN @Orden='number' AND @Direccion='asc' THEN v.Numero END ASC,CASE WHEN @Orden='number' AND @Direccion='desc' THEN v.Numero END DESC,
          CASE WHEN @Orden='customer' AND @Direccion='asc' THEN v.ClienteNombre END ASC,CASE WHEN @Orden='customer' AND @Direccion='desc' THEN v.ClienteNombre END DESC,
          CASE WHEN @Orden='cashier' AND @Direccion='asc' THEN v.CajeroNombre END ASC,CASE WHEN @Orden='cashier' AND @Direccion='desc' THEN v.CajeroNombre END DESC,
          CASE WHEN @Orden='total' AND @Direccion='asc' THEN v.Total END ASC,CASE WHEN @Orden='total' AND @Direccion='desc' THEN v.Total END DESC,
          v.FacturaId DESC OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        SELECT COUNT_BIG(*) AS operationCount,CONVERT(varchar(40),COALESCE(SUM(v.Subtotal),0)) AS subtotal,
               CONVERT(varchar(40),COALESCE(SUM(v.IVA),0)) AS tax,CONVERT(varchar(40),COALESCE(SUM(v.Total),0)) AS total,
               MAX(v.Moneda) AS currency FROM dbo.fn_ObtenerHistoricoVentas(@DesdeUtc,@HastaUtc) v
        WHERE NULLIF(@Busqueda,N'') IS NULL OR CONVERT(nvarchar(30),v.Numero) LIKE N'%'+@Busqueda+N'%'
           OR v.ClienteNombre LIKE N'%'+@Busqueda+N'%' OR v.CajeroNombre LIKE N'%'+@Busqueda+N'%';
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ObtenerResumenInicio
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Zona sysname,@Hoy date,@DesdeUtc datetime2(3),@HastaUtc datetime2(3);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,NULL,0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        SELECT @Zona=ZonaHorariaSql FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1;
        SET @Hoy=CONVERT(date,(SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE @Zona);
        SET @DesdeUtc=CONVERT(datetime2(3),(CONVERT(datetime2(0),@Hoy) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        SET @HastaUtc=CONVERT(datetime2(3),(DATEADD(day,1,CONVERT(datetime2(0),@Hoy)) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        IF dbo.fn_TienePermiso(@UsuarioId,'REPORTES_LEER')=1
            SELECT COUNT_BIG(*) AS saleCount,CONVERT(varchar(40),COALESCE(SUM(Subtotal),0)) AS subtotal,
                   CONVERT(varchar(40),COALESCE(SUM(IVA),0)) AS tax,CONVERT(varchar(40),COALESCE(SUM(Total),0)) AS total,
                   CONVERT(varchar(40),COALESCE(CONVERT(decimal(19,2),ROUND(AVG(CONVERT(decimal(28,6),Total)),2)),0)) AS averageTicket,
                   COALESCE(MAX(Moneda),(SELECT MonedaCodigo FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1)) AS currency,@Hoy AS localDate
            FROM dbo.Factura WHERE FechaUtc>=@DesdeUtc AND FechaUtc<@HastaUtc;
        ELSE
            SELECT CONVERT(bigint,NULL) AS saleCount,CONVERT(varchar(40),NULL) AS subtotal,CONVERT(varchar(40),NULL) AS tax,
                   CONVERT(varchar(40),NULL) AS total,CONVERT(varchar(40),NULL) AS averageTicket,
                   CONVERT(char(3),NULL) AS currency,CONVERT(date,NULL) AS localDate WHERE 1=0;

        SELECT code,label,route FROM
        (
            SELECT 'VENTAS_CREAR' code,N'Nueva venta' label,'/ventas/nueva' route,1 orden WHERE dbo.fn_TienePermiso(@UsuarioId,'VENTAS_CREAR')=1
            UNION ALL SELECT 'PRODUCTOS_GESTIONAR',N'Productos','/productos',2 WHERE dbo.fn_TienePermiso(@UsuarioId,'PRODUCTOS_GESTIONAR')=1
            UNION ALL SELECT 'CLIENTES_GESTIONAR',N'Clientes','/clientes',3 WHERE dbo.fn_TienePermiso(@UsuarioId,'CLIENTES_GESTIONAR')=1
            UNION ALL SELECT 'REPORTES_LEER',N'Reportes','/reportes/ventas',4 WHERE dbo.fn_TienePermiso(@UsuarioId,'REPORTES_LEER')=1
            UNION ALL SELECT 'AUDITORIA_LEER',N'Auditoria','/auditoria',5 WHERE dbo.fn_TienePermiso(@UsuarioId,'AUDITORIA_LEER')=1
            UNION ALL SELECT 'USUARIOS_GESTIONAR',N'Usuarios','/usuarios',6 WHERE dbo.fn_TienePermiso(@UsuarioId,'USUARIOS_GESTIONAR')=1
            UNION ALL SELECT 'ROLES_GESTIONAR',N'Roles y permisos','/roles',7 WHERE dbo.fn_TienePermiso(@UsuarioId,'ROLES_GESTIONAR')=1
        ) s ORDER BY orden;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO
