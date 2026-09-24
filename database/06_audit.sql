USE [$(DatabaseName)];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER TRIGGER dbo.trg_Usuario_AuditoriaDML ON dbo.Usuario
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Usuario',CASE WHEN i.UsuarioId IS NULL THEN 'DELETE' WHEN d.UsuarioId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.UsuarioId,d.UsuarioId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.UsuarioId IS NULL THEN NULL ELSE (SELECT d.UsuarioId AS usuarioId,d.NombreUsuario AS nombreUsuario,
        d.NombreVisible AS nombreVisible,d.CorreoRecuperacion AS correoRecuperacion,d.DebeCambiarPassword AS debeCambiarPassword,
        d.Activo AS activo,d.VersionSeguridad AS versionSeguridad FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.UsuarioId IS NULL THEN NULL ELSE (SELECT i.UsuarioId AS usuarioId,i.NombreUsuario AS nombreUsuario,
        i.NombreVisible AS nombreVisible,i.CorreoRecuperacion AS correoRecuperacion,i.DebeCambiarPassword AS debeCambiarPassword,
        i.Activo AS activo,i.VersionSeguridad AS versionSeguridad FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.UsuarioId=i.UsuarioId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_Rol_AuditoriaDML ON dbo.Rol
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Rol',CASE WHEN i.RolId IS NULL THEN 'DELETE' WHEN d.RolId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.RolId,d.RolId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.RolId IS NULL THEN NULL ELSE (SELECT d.RolId AS rolId,d.Nombre AS nombre,d.Descripcion AS descripcion,
        d.EsAdministrador AS esAdministrador,d.Activo AS activo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.RolId IS NULL THEN NULL ELSE (SELECT i.RolId AS rolId,i.Nombre AS nombre,i.Descripcion AS descripcion,
        i.EsAdministrador AS esAdministrador,i.Activo AS activo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.RolId=i.RolId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_UsuarioRol_AuditoriaDML ON dbo.Usuario_Rol
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Usuario_Rol',CASE WHEN i.UsuarioId IS NULL THEN 'DELETE' WHEN d.UsuarioId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONCAT(COALESCE(i.UsuarioId,d.UsuarioId),N':',COALESCE(i.RolId,d.RolId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.UsuarioId IS NULL THEN NULL ELSE (SELECT d.UsuarioId AS usuarioId,d.RolId AS rolId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.UsuarioId IS NULL THEN NULL ELSE (SELECT i.UsuarioId AS usuarioId,i.RolId AS rolId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.UsuarioId=i.UsuarioId AND d.RolId=i.RolId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_RolPermiso_AuditoriaDML ON dbo.Rol_Permiso
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Rol_Permiso',CASE WHEN i.RolId IS NULL THEN 'DELETE' WHEN d.RolId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONCAT(COALESCE(i.RolId,d.RolId),N':',COALESCE(i.PermisoId,d.PermisoId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.RolId IS NULL THEN NULL ELSE (SELECT d.RolId AS rolId,d.PermisoId AS permisoId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.RolId IS NULL THEN NULL ELSE (SELECT i.RolId AS rolId,i.PermisoId AS permisoId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.RolId=i.RolId AND d.PermisoId=i.PermisoId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_Producto_AuditoriaDML ON dbo.Producto
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Producto',CASE WHEN i.ProductoId IS NULL THEN 'DELETE' WHEN d.ProductoId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.ProductoId,d.ProductoId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.ProductoId IS NULL THEN NULL ELSE (SELECT d.ProductoId AS productoId,d.Codigo AS codigo,d.Descripcion AS descripcion,
        d.Unidad AS unidad,d.Precio AS precio,d.Stock AS stock,d.Activo AS activo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.ProductoId IS NULL THEN NULL ELSE (SELECT i.ProductoId AS productoId,i.Codigo AS codigo,i.Descripcion AS descripcion,
        i.Unidad AS unidad,i.Precio AS precio,i.Stock AS stock,i.Activo AS activo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.ProductoId=i.ProductoId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_Cliente_AuditoriaDML ON dbo.Cliente
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Cliente',CASE WHEN i.ClienteId IS NULL THEN 'DELETE' WHEN d.ClienteId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.ClienteId,d.ClienteId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.ClienteId IS NULL THEN NULL ELSE (SELECT d.ClienteId AS clienteId,d.Identificador AS identificador,d.Nombre AS nombre,
        d.Correo AS correo,d.Telefono AS telefono,d.Activo AS activo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.ClienteId IS NULL THEN NULL ELSE (SELECT i.ClienteId AS clienteId,i.Identificador AS identificador,i.Nombre AS nombre,
        i.Correo AS correo,i.Telefono AS telefono,i.Activo AS activo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.ClienteId=i.ClienteId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_Factura_AuditoriaDML ON dbo.Factura
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Factura',CASE WHEN i.FacturaId IS NULL THEN 'DELETE' WHEN d.FacturaId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.FacturaId,d.FacturaId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.FacturaId IS NULL THEN NULL ELSE (SELECT d.FacturaId AS facturaId,d.Numero AS numero,d.Estado AS estado,d.ClienteId AS clienteId,
        d.UsuarioId AS usuarioId,d.Moneda AS moneda,d.TasaIVA AS tasaIVA,d.Subtotal AS subtotal,d.IVA AS iva,d.Total AS total FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.FacturaId IS NULL THEN NULL ELSE (SELECT i.FacturaId AS facturaId,i.Numero AS numero,i.Estado AS estado,i.ClienteId AS clienteId,
        i.UsuarioId AS usuarioId,i.Moneda AS moneda,i.TasaIVA AS tasaIVA,i.Subtotal AS subtotal,i.IVA AS iva,i.Total AS total FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.FacturaId=i.FacturaId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_DetalleFactura_AuditoriaDML ON dbo.Detalle_Factura
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'Detalle_Factura',CASE WHEN i.DetalleFacturaId IS NULL THEN 'DELETE' WHEN d.DetalleFacturaId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.DetalleFacturaId,d.DetalleFacturaId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.DetalleFacturaId IS NULL THEN NULL ELSE (SELECT d.DetalleFacturaId AS detalleId,d.FacturaId AS facturaId,d.ProductoId AS productoId,
        d.Cantidad AS cantidad,d.PrecioUnitario AS precioUnitario,d.Importe AS importe FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.DetalleFacturaId IS NULL THEN NULL ELSE (SELECT i.DetalleFacturaId AS detalleId,i.FacturaId AS facturaId,i.ProductoId AS productoId,
        i.Cantidad AS cantidad,i.PrecioUnitario AS precioUnitario,i.Importe AS importe FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.DetalleFacturaId=i.DetalleFacturaId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_MovimientoCaja_AuditoriaDML ON dbo.MovimientoCaja
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'MovimientoCaja',CASE WHEN i.MovimientoCajaId IS NULL THEN 'DELETE' WHEN d.MovimientoCajaId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.MovimientoCajaId,d.MovimientoCajaId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.MovimientoCajaId IS NULL THEN NULL ELSE (SELECT d.MovimientoCajaId AS movimientoId,d.FacturaId AS facturaId,
        d.Tipo AS tipo,d.Importe AS importe,d.Moneda AS moneda,d.UsuarioId AS usuarioId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.MovimientoCajaId IS NULL THEN NULL ELSE (SELECT i.MovimientoCajaId AS movimientoId,i.FacturaId AS facturaId,
        i.Tipo AS tipo,i.Importe AS importe,i.Moneda AS moneda,i.UsuarioId AS usuarioId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.MovimientoCajaId=i.MovimientoCajaId;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_PreferenciaUsuario_AuditoriaDML ON dbo.PreferenciaUsuario
AFTER INSERT,UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Bitacora_Transacciones
      (Tabla,Operacion,RegistroId,UsuarioAplicacionId,UsuarioAplicacion,DireccionIP,CorrelationId,Motivo,ValoresAnteriores,ValoresNuevos)
    SELECT N'PreferenciaUsuario',CASE WHEN i.UsuarioId IS NULL THEN 'DELETE' WHEN d.UsuarioId IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
      CONVERT(nvarchar(200),COALESCE(i.UsuarioId,d.UsuarioId)),TRY_CONVERT(int,SESSION_CONTEXT(N'UsuarioId')),
      TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),TRY_CONVERT(varchar(45),SESSION_CONTEXT(N'DireccionIP')),
      TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),TRY_CONVERT(nvarchar(250),SESSION_CONTEXT(N'MotivoAuditoria')),
      CASE WHEN d.UsuarioId IS NULL THEN NULL ELSE (SELECT d.UsuarioId AS usuarioId,d.Tema AS tema FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END,
      CASE WHEN i.UsuarioId IS NULL THEN NULL ELSE (SELECT i.UsuarioId AS usuarioId,i.Tema AS tema FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) END
    FROM inserted i FULL OUTER JOIN deleted d ON d.UsuarioId=i.UsuarioId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarBitacoraAcceso
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Pagina int=1,@TamanoPagina tinyint=25,@Busqueda nvarchar(160)=NULL,@Orden varchar(40)='date',@Direccion varchar(4)='desc',
    @FechaDesde varchar(10)=NULL,@FechaHasta varchar(10)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc') OR @Orden NOT IN('date','actor','operation','object')
        THROW 51006,N'Filtros no validos.',1;
    DECLARE @Desde date=TRY_CONVERT(date,@FechaDesde,23),@Hasta date=TRY_CONVERT(date,@FechaHasta,23);
    IF (@FechaDesde IS NOT NULL AND @Desde IS NULL) OR (@FechaHasta IS NOT NULL AND @Hasta IS NULL) OR (@Desde IS NOT NULL AND @Hasta IS NOT NULL AND @Desde>@Hasta)
        THROW 51006,N'Rango de fechas no valido.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Zona sysname,@DesdeUtc datetime2(3),@HastaUtc datetime2(3),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'AUDITORIA_LEER',0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        SELECT @Zona=ZonaHorariaSql FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1;
        IF @Desde IS NOT NULL SET @DesdeUtc=CONVERT(datetime2(3),(CONVERT(datetime2(0),@Desde) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        IF @Hasta IS NOT NULL SET @HastaUtc=CONVERT(datetime2(3),(DATEADD(day,1,CONVERT(datetime2(0),@Hasta)) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        SELECT @Total=COUNT_BIG(*) FROM dbo.Bitacora_Acceso b LEFT JOIN dbo.Usuario u ON u.UsuarioId=b.UsuarioId
        WHERE (@DesdeUtc IS NULL OR b.FechaUtc>=@DesdeUtc) AND (@HastaUtc IS NULL OR b.FechaUtc<@HastaUtc)
          AND (NULLIF(@Busqueda,N'') IS NULL OR b.NombreUsuarioIntentado LIKE N'%'+@Busqueda+N'%' OR u.NombreUsuario LIKE N'%'+@Busqueda+N'%'
               OR b.Resultado LIKE N'%'+@Busqueda+N'%' OR b.DireccionIP LIKE N'%'+@Busqueda+N'%');
        SELECT b.BitacoraAccesoId AS id,b.FechaUtc AS occurredAt,u.NombreUsuario AS actor,b.NombreUsuarioIntentado AS attemptedUsername,
               b.Resultado AS result,b.MotivoInterno AS internalReason,b.DireccionIP AS ipAddress,b.PrincipalSql AS sqlPrincipal,
               b.HostName AS hostName,b.AppName AS appName,b.CorrelationId AS correlationId
        FROM dbo.Bitacora_Acceso b LEFT JOIN dbo.Usuario u ON u.UsuarioId=b.UsuarioId
        WHERE (@DesdeUtc IS NULL OR b.FechaUtc>=@DesdeUtc) AND (@HastaUtc IS NULL OR b.FechaUtc<@HastaUtc)
          AND (NULLIF(@Busqueda,N'') IS NULL OR b.NombreUsuarioIntentado LIKE N'%'+@Busqueda+N'%' OR u.NombreUsuario LIKE N'%'+@Busqueda+N'%'
               OR b.Resultado LIKE N'%'+@Busqueda+N'%' OR b.DireccionIP LIKE N'%'+@Busqueda+N'%')
        ORDER BY CASE WHEN @Orden='date' AND @Direccion='asc' THEN b.FechaUtc END ASC,CASE WHEN @Orden='date' AND @Direccion='desc' THEN b.FechaUtc END DESC,
          CASE WHEN @Orden='actor' AND @Direccion='asc' THEN COALESCE(u.NombreUsuario,b.NombreUsuarioIntentado COLLATE Latin1_General_100_CI_AI) END ASC,
          CASE WHEN @Orden='actor' AND @Direccion='desc' THEN COALESCE(u.NombreUsuario,b.NombreUsuarioIntentado COLLATE Latin1_General_100_CI_AI) END DESC,
          CASE WHEN @Orden='operation' AND @Direccion='asc' THEN b.Resultado END ASC,CASE WHEN @Orden='operation' AND @Direccion='desc' THEN b.Resultado END DESC,
          b.BitacoraAccesoId DESC OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarAuditoriaDML
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Pagina int=1,@TamanoPagina tinyint=25,@Busqueda nvarchar(160)=NULL,@Orden varchar(40)='date',@Direccion varchar(4)='desc',
    @FechaDesde varchar(10)=NULL,@FechaHasta varchar(10)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc') OR @Orden NOT IN('date','actor','operation','object')
        THROW 51006,N'Filtros no validos.',1;
    DECLARE @Desde date=TRY_CONVERT(date,@FechaDesde,23),@Hasta date=TRY_CONVERT(date,@FechaHasta,23);
    IF (@FechaDesde IS NOT NULL AND @Desde IS NULL) OR (@FechaHasta IS NOT NULL AND @Hasta IS NULL) OR (@Desde IS NOT NULL AND @Hasta IS NOT NULL AND @Desde>@Hasta)
        THROW 51006,N'Rango de fechas no valido.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Zona sysname,@DesdeUtc datetime2(3),@HastaUtc datetime2(3),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'AUDITORIA_LEER',0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        SELECT @Zona=ZonaHorariaSql FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1;
        IF @Desde IS NOT NULL SET @DesdeUtc=CONVERT(datetime2(3),(CONVERT(datetime2(0),@Desde) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        IF @Hasta IS NOT NULL SET @HastaUtc=CONVERT(datetime2(3),(DATEADD(day,1,CONVERT(datetime2(0),@Hasta)) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        SELECT @Total=COUNT_BIG(*) FROM dbo.fn_ConsultarAuditoriaDML(@DesdeUtc,@HastaUtc,@Busqueda);
        SELECT BitacoraTransaccionId AS id,FechaUtc AS occurredAt,Tabla AS objectName,Operacion AS operation,RegistroId AS recordId,
               UsuarioAplicacionId AS actorId,UsuarioAplicacion AS actor,PrincipalSql AS sqlPrincipal,HostName AS hostName,AppName AS appName,
               DireccionIP AS ipAddress,CorrelationId AS correlationId,Motivo AS reason,ValoresAnteriores AS beforeValues,ValoresNuevos AS afterValues
        FROM dbo.fn_ConsultarAuditoriaDML(@DesdeUtc,@HastaUtc,@Busqueda)
        ORDER BY CASE WHEN @Orden='date' AND @Direccion='asc' THEN FechaUtc END ASC,CASE WHEN @Orden='date' AND @Direccion='desc' THEN FechaUtc END DESC,
          CASE WHEN @Orden='actor' AND @Direccion='asc' THEN UsuarioAplicacion END ASC,CASE WHEN @Orden='actor' AND @Direccion='desc' THEN UsuarioAplicacion END DESC,
          CASE WHEN @Orden='operation' AND @Direccion='asc' THEN Operacion END ASC,CASE WHEN @Orden='operation' AND @Direccion='desc' THEN Operacion END DESC,
          CASE WHEN @Orden='object' AND @Direccion='asc' THEN Tabla END ASC,CASE WHEN @Orden='object' AND @Direccion='desc' THEN Tabla END DESC,
          BitacoraTransaccionId DESC OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarAuditoriaDDL
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Pagina int=1,@TamanoPagina tinyint=25,@Busqueda nvarchar(160)=NULL,@Orden varchar(40)='date',@Direccion varchar(4)='desc',
    @FechaDesde varchar(10)=NULL,@FechaHasta varchar(10)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc') OR @Orden NOT IN('date','actor','operation','object')
        THROW 51006,N'Filtros no validos.',1;
    DECLARE @Desde date=TRY_CONVERT(date,@FechaDesde,23),@Hasta date=TRY_CONVERT(date,@FechaHasta,23);
    IF (@FechaDesde IS NOT NULL AND @Desde IS NULL) OR (@FechaHasta IS NOT NULL AND @Hasta IS NULL) OR (@Desde IS NOT NULL AND @Hasta IS NOT NULL AND @Desde>@Hasta)
        THROW 51006,N'Rango de fechas no valido.',1;
    DECLARE @UsuarioId int,@Usuario varchar(50),@Nombre nvarchar(120),@Zona sysname,@DesdeUtc datetime2(3),@HastaUtc datetime2(3),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'AUDITORIA_LEER',0,1,@UsuarioId OUTPUT,@Usuario OUTPUT,@Nombre OUTPUT;
        SELECT @Zona=ZonaHorariaSql FROM dbo.ConfiguracionSistema WHERE ConfiguracionId=1;
        IF @Desde IS NOT NULL SET @DesdeUtc=CONVERT(datetime2(3),(CONVERT(datetime2(0),@Desde) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        IF @Hasta IS NOT NULL SET @HastaUtc=CONVERT(datetime2(3),(DATEADD(day,1,CONVERT(datetime2(0),@Hasta)) AT TIME ZONE @Zona) AT TIME ZONE 'UTC');
        SELECT @Total=COUNT_BIG(*) FROM dbo.Bitacora_DDL b WHERE (@DesdeUtc IS NULL OR b.FechaUtc>=@DesdeUtc) AND (@HastaUtc IS NULL OR b.FechaUtc<@HastaUtc)
          AND (NULLIF(@Busqueda,N'') IS NULL OR b.TipoEvento LIKE N'%'+@Busqueda+N'%' OR b.NombreObjeto LIKE N'%'+@Busqueda+N'%'
               OR b.PrincipalSql LIKE N'%'+@Busqueda+N'%' OR b.Comando LIKE N'%'+@Busqueda+N'%');
        SELECT b.BitacoraDDLId AS id,b.FechaUtc AS occurredAt,b.TipoEvento AS operation,b.TipoObjeto AS objectType,b.NombreObjeto AS objectName,
               b.Esquema AS schemaName,b.Comando AS commandText,b.PrincipalSql AS sqlPrincipal,b.UsuarioAplicacion AS actor,
               b.HostName AS hostName,b.AppName AS appName,b.CorrelationId AS correlationId
        FROM dbo.Bitacora_DDL b WHERE (@DesdeUtc IS NULL OR b.FechaUtc>=@DesdeUtc) AND (@HastaUtc IS NULL OR b.FechaUtc<@HastaUtc)
          AND (NULLIF(@Busqueda,N'') IS NULL OR b.TipoEvento LIKE N'%'+@Busqueda+N'%' OR b.NombreObjeto LIKE N'%'+@Busqueda+N'%'
               OR b.PrincipalSql LIKE N'%'+@Busqueda+N'%' OR b.Comando LIKE N'%'+@Busqueda+N'%')
        ORDER BY CASE WHEN @Orden='date' AND @Direccion='asc' THEN b.FechaUtc END ASC,CASE WHEN @Orden='date' AND @Direccion='desc' THEN b.FechaUtc END DESC,
          CASE WHEN @Orden='actor' AND @Direccion='asc' THEN b.PrincipalSql END ASC,CASE WHEN @Orden='actor' AND @Direccion='desc' THEN b.PrincipalSql END DESC,
          CASE WHEN @Orden='operation' AND @Direccion='asc' THEN b.TipoEvento END ASC,CASE WHEN @Orden='operation' AND @Direccion='desc' THEN b.TipoEvento END DESC,
          CASE WHEN @Orden='object' AND @Direccion='asc' THEN b.NombreObjeto END ASC,CASE WHEN @Orden='object' AND @Direccion='desc' THEN b.NombreObjeto END DESC,
          b.BitacoraDDLId DESC OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER TRIGGER trg_SecureFinance_AuditoriaDDL
ON DATABASE
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Evento xml=EVENTDATA();
    IF @Evento.value('(/EVENT_INSTANCE/ObjectName)[1]','sysname') IN (N'Bitacora_DDL',N'trg_SecureFinance_AuditoriaDDL') RETURN;
    DECLARE @EventoSeguro xml=
    (
        SELECT
            @Evento.value('(/EVENT_INSTANCE/EventType)[1]','sysname') AS [EventType],
            @Evento.value('(/EVENT_INSTANCE/PostTime)[1]','datetime2(3)') AS [PostTime],
            @Evento.value('(/EVENT_INSTANCE/LoginName)[1]','sysname') AS [LoginName],
            @Evento.value('(/EVENT_INSTANCE/ObjectType)[1]','sysname') AS [ObjectType],
            @Evento.value('(/EVENT_INSTANCE/SchemaName)[1]','sysname') AS [SchemaName],
            @Evento.value('(/EVENT_INSTANCE/ObjectName)[1]','sysname') AS [ObjectName]
        FOR XML PATH('EVENT_INSTANCE'),TYPE
    );
    INSERT dbo.Bitacora_DDL
      (TipoEvento,TipoObjeto,NombreObjeto,Esquema,Comando,PrincipalSql,UsuarioAplicacion,HostName,AppName,CorrelationId,DatosEvento)
    VALUES
      (@Evento.value('(/EVENT_INSTANCE/EventType)[1]','sysname'),@Evento.value('(/EVENT_INSTANCE/ObjectType)[1]','sysname'),
       @Evento.value('(/EVENT_INSTANCE/ObjectName)[1]','sysname'),@Evento.value('(/EVENT_INSTANCE/SchemaName)[1]','sysname'),
       NULL,SUSER_SNAME(),
       TRY_CONVERT(varchar(50),SESSION_CONTEXT(N'UsuarioAplicacion')),HOST_NAME(),APP_NAME(),
       TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),@EventoSeguro);
END;
GO
