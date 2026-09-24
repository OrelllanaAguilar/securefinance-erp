USE [$(DatabaseName)];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularSubtotal
(
    @Cantidad int,
    @Precio decimal(19,2)
)
RETURNS decimal(19,2)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CONVERT(decimal(19,2), ROUND(CONVERT(decimal(28,4), @Cantidad) * @Precio, 2));
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularIVA
(
    @Subtotal decimal(19,2)
)
RETURNS decimal(19,2)
AS
BEGIN
    DECLARE @Tasa decimal(9,6);
    SELECT @Tasa = TasaIVA FROM dbo.ConfiguracionSistema WHERE ConfiguracionId = 1;
    RETURN CONVERT(decimal(19,2), ROUND(@Subtotal * COALESCE(@Tasa, CONVERT(decimal(9,6), 0.120000)), 2));
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_ContrasenaCumplePolitica
(
    @Contrasena nvarchar(128)
)
RETURNS bit
WITH SCHEMABINDING
AS
BEGIN
    IF @Contrasena IS NULL RETURN 0;
    IF DATALENGTH(@Contrasena) / 2 NOT BETWEEN 12 AND 128 RETURN 0;
    IF @Contrasena COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[A-Z]%' RETURN 0;
    IF @Contrasena COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[a-z]%' RETURN 0;
    IF @Contrasena COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[0-9]%' RETURN 0;
    IF @Contrasena COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^A-Za-z0-9]%' RETURN 0;
    RETURN 1;
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_TienePermiso
(
    @UsuarioId int,
    @Codigo varchar(60)
)
RETURNS bit
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Tiene bit = 0;
    IF EXISTS
    (
        SELECT 1
        FROM dbo.Usuario_Rol AS ur
        JOIN dbo.Rol AS r ON r.RolId = ur.RolId AND r.Activo = 1
        JOIN dbo.Rol_Permiso AS rp ON rp.RolId = r.RolId
        JOIN dbo.Permiso AS p ON p.PermisoId = rp.PermisoId AND p.Activo = 1
        WHERE ur.UsuarioId = @UsuarioId
          AND p.Codigo = @Codigo
    ) SET @Tiene = 1;
    RETURN @Tiene;
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_ObtenerHistoricoVentas
(
    @FechaDesdeUtc datetime2(3),
    @FechaHastaExclusivaUtc datetime2(3)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        f.FacturaId,
        f.Numero,
        f.FechaUtc,
        f.Estado,
        f.ClienteId,
        f.ClienteIdentificador,
        f.ClienteNombre,
        f.UsuarioId,
        f.CajeroNombre,
        f.Moneda,
        f.Subtotal,
        f.IVA,
        f.Total
    FROM dbo.Factura AS f
    WHERE f.Estado = 'Confirmada'
      AND f.FechaUtc >= @FechaDesdeUtc
      AND f.FechaUtc < @FechaHastaExclusivaUtc
);
GO

CREATE OR ALTER FUNCTION dbo.fn_ConsultarAuditoriaDML
(
    @FechaDesdeUtc datetime2(3) = NULL,
    @FechaHastaExclusivaUtc datetime2(3) = NULL,
    @Busqueda nvarchar(160) = NULL
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        b.BitacoraTransaccionId,
        b.FechaUtc,
        b.Tabla,
        b.Operacion,
        b.RegistroId,
        b.UsuarioAplicacionId,
        b.UsuarioAplicacion,
        b.PrincipalSql,
        b.HostName,
        b.AppName,
        b.DireccionIP,
        b.CorrelationId,
        b.Motivo,
        b.ValoresAnteriores,
        b.ValoresNuevos
    FROM dbo.Bitacora_Transacciones AS b
    WHERE (@FechaDesdeUtc IS NULL OR b.FechaUtc >= @FechaDesdeUtc)
      AND (@FechaHastaExclusivaUtc IS NULL OR b.FechaUtc < @FechaHastaExclusivaUtc)
      AND
      (
          NULLIF(@Busqueda, N'') IS NULL
          OR b.Tabla LIKE N'%' + @Busqueda + N'%'
          OR b.Operacion LIKE N'%' + @Busqueda + N'%'
          OR b.RegistroId LIKE N'%' + @Busqueda + N'%'
          OR b.UsuarioAplicacion LIKE N'%' + @Busqueda + N'%'
          OR CONVERT(nvarchar(36), b.CorrelationId) LIKE N'%' + @Busqueda + N'%'
      )
);
GO
