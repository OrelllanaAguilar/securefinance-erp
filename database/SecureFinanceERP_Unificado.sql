/*
    SecureFinance ERP - Script SQL unificado

    Contenido:
      - Creacion y configuracion de la base de datos.
      - Tablas, llaves primarias/foraneas, restricciones e indices.
      - Funciones escalares y funciones con valor de tabla (TVF).
      - Stored Procedures, triggers DML/DDL, roles y permisos internos.
      - Usuario administrador bootstrap y datos semilla demostrativos.

    Requisitos:
      - SQL Server 2022 (16.x) o posterior.
      - Ejecutar con SQLCMD desde la raiz del repositorio.
      - DatabaseName debe terminar en _Test porque incluye datos demo.
      - La clave bootstrap debe tener 12-128 caracteres, mayuscula,
        minuscula, numero y simbolo.

    Ejemplo:
      sqlcmd -S ".\SQLEXPRESS" -E -C -b `
        -v DatabaseName="SecureFinanceERP_Entrega_Test" `
           BootstrapUsername="admin.local" `
           BootstrapDisplayName="AdministradorLocal" `
           BootstrapPassword="REEMPLAZAR_POR_CLAVE_SEGURA" `
        -i ".\database\SecureFinanceERP_Unificado.sql"

    El script es idempotente: conserva datos existentes y no elimina la base.
    Si el usuario bootstrap ya existe, no cambia su contrasena.
*/

:on error exit
PRINT N'Iniciando instalacion unificada de SecureFinance ERP...';
GO

/* ===== INICIO: database\00_database.sql ===== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF TRY_CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 16
    THROW 51006, N'SecureFinance ERP requiere SQL Server 2022 (16.x) o posterior.', 1;

DECLARE @DatabaseNameInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(DatabaseName))';
IF LEN(@DatabaseNameInput) NOT BETWEEN 1 AND 128
   OR @DatabaseNameInput LIKE N'%[^A-Za-z0-9_]%' COLLATE Latin1_General_100_BIN2
    THROW 51006,N'DatabaseName debe contener solo letras ASCII, numeros o guion bajo.',1;

IF DB_ID(@DatabaseNameInput) IS NULL
BEGIN
    DECLARE @CreateDatabase nvarchar(max) =
        N'CREATE DATABASE ' + QUOTENAME(CONVERT(sysname,@DatabaseNameInput)) + N';';
    EXEC sys.sp_executesql @CreateDatabase;
END;
GO

USE [$(DatabaseName)];
GO

DECLARE @NivelCompatibilidad smallint =
    CASE WHEN TRY_CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) >= 17 THEN 170 ELSE 160 END;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID()) <> @NivelCompatibilidad
BEGIN
    DECLARE @AlterarCompatibilidad nvarchar(200) =
        N'ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = ' + CONVERT(nvarchar(3), @NivelCompatibilidad) + N';';
    EXEC sys.sp_executesql @AlterarCompatibilidad;
END;
GO

ALTER DATABASE CURRENT SET ANSI_NULL_DEFAULT ON;
ALTER DATABASE CURRENT SET ANSI_NULLS ON;
ALTER DATABASE CURRENT SET ANSI_PADDING ON;
ALTER DATABASE CURRENT SET ANSI_WARNINGS ON;
ALTER DATABASE CURRENT SET ARITHABORT ON;
ALTER DATABASE CURRENT SET CONCAT_NULL_YIELDS_NULL ON;
ALTER DATABASE CURRENT SET QUOTED_IDENTIFIER ON;
GO
/* ===== FIN: database\00_database.sql ===== */

/* ===== INICIO: database\01_schema.sql ===== */
USE [$(DatabaseName)];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Permiso', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Permiso
    (
        PermisoId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Permiso PRIMARY KEY,
        Codigo varchar(60) COLLATE Latin1_General_100_CI_AI NOT NULL,
        Nombre nvarchar(120) NOT NULL,
        Modulo varchar(40) NOT NULL,
        Activo bit NOT NULL CONSTRAINT DF_Permiso_Activo DEFAULT (1),
        CreadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Permiso_CreadoUtc DEFAULT (SYSUTCDATETIME()),
        ActualizadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Permiso_ActualizadoUtc DEFAULT (SYSUTCDATETIME()),
        VersionFila rowversion NOT NULL,
        CONSTRAINT UQ_Permiso_Codigo UNIQUE (Codigo),
        CONSTRAINT CK_Permiso_Codigo CHECK (Codigo NOT LIKE '%[^A-Z0-9_]%' AND LEN(Codigo) BETWEEN 3 AND 60)
    );
END;
GO

IF OBJECT_ID(N'dbo.Rol', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Rol
    (
        RolId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Rol PRIMARY KEY,
        Nombre varchar(60) COLLATE Latin1_General_100_CI_AI NOT NULL,
        Descripcion nvarchar(250) NULL,
        EsAdministrador bit NOT NULL CONSTRAINT DF_Rol_EsAdministrador DEFAULT (0),
        Activo bit NOT NULL CONSTRAINT DF_Rol_Activo DEFAULT (1),
        CreadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Rol_CreadoUtc DEFAULT (SYSUTCDATETIME()),
        ActualizadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Rol_ActualizadoUtc DEFAULT (SYSUTCDATETIME()),
        VersionFila rowversion NOT NULL,
        CONSTRAINT UQ_Rol_Nombre UNIQUE (Nombre),
        CONSTRAINT CK_Rol_Nombre CHECK (LEN(Nombre) BETWEEN 3 AND 60)
    );
END;
GO

IF OBJECT_ID(N'dbo.Usuario', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Usuario
    (
        UsuarioId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Usuario PRIMARY KEY,
        NombreUsuario varchar(50) COLLATE Latin1_General_100_CI_AI NOT NULL,
        NombreVisible nvarchar(120) NOT NULL,
        CorreoRecuperacion nvarchar(254) NULL,
        PasswordHash varbinary(64) NOT NULL,
        PasswordSalt varbinary(32) NOT NULL,
        DebeCambiarPassword bit NOT NULL CONSTRAINT DF_Usuario_DebeCambiarPassword DEFAULT (1),
        Activo bit NOT NULL CONSTRAINT DF_Usuario_Activo DEFAULT (1),
        VersionSeguridad int NOT NULL CONSTRAINT DF_Usuario_VersionSeguridad DEFAULT (1),
        CreadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Usuario_CreadoUtc DEFAULT (SYSUTCDATETIME()),
        ActualizadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Usuario_ActualizadoUtc DEFAULT (SYSUTCDATETIME()),
        UltimoCambioPasswordUtc datetime2(3) NOT NULL CONSTRAINT DF_Usuario_UltimoCambioPasswordUtc DEFAULT (SYSUTCDATETIME()),
        VersionFila rowversion NOT NULL,
        CONSTRAINT UQ_Usuario_NombreUsuario UNIQUE (NombreUsuario),
        CONSTRAINT CK_Usuario_NombreUsuario CHECK
        (
            LEN(NombreUsuario) BETWEEN 3 AND 50
            AND NombreUsuario NOT LIKE '%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
        ),
        CONSTRAINT CK_Usuario_NombreVisible CHECK (LEN(NombreVisible) BETWEEN 2 AND 120),
        CONSTRAINT CK_Usuario_Salt CHECK (DATALENGTH(PasswordSalt) = 32),
        CONSTRAINT CK_Usuario_Hash CHECK (DATALENGTH(PasswordHash) = 64),
        CONSTRAINT CK_Usuario_VersionSeguridad CHECK (VersionSeguridad > 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.Usuario_Rol', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Usuario_Rol
    (
        UsuarioId int NOT NULL,
        RolId int NOT NULL,
        AsignadoUtc datetime2(3) NOT NULL CONSTRAINT DF_UsuarioRol_AsignadoUtc DEFAULT (SYSUTCDATETIME()),
        AsignadoPorUsuarioId int NULL,
        CONSTRAINT PK_Usuario_Rol PRIMARY KEY (UsuarioId, RolId),
        CONSTRAINT FK_UsuarioRol_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT FK_UsuarioRol_Rol FOREIGN KEY (RolId) REFERENCES dbo.Rol(RolId),
        CONSTRAINT FK_UsuarioRol_AsignadoPor FOREIGN KEY (AsignadoPorUsuarioId) REFERENCES dbo.Usuario(UsuarioId)
    );
END;
GO

IF OBJECT_ID(N'dbo.Rol_Permiso', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Rol_Permiso
    (
        RolId int NOT NULL,
        PermisoId int NOT NULL,
        AsignadoUtc datetime2(3) NOT NULL CONSTRAINT DF_RolPermiso_AsignadoUtc DEFAULT (SYSUTCDATETIME()),
        AsignadoPorUsuarioId int NULL,
        CONSTRAINT PK_Rol_Permiso PRIMARY KEY (RolId, PermisoId),
        CONSTRAINT FK_RolPermiso_Rol FOREIGN KEY (RolId) REFERENCES dbo.Rol(RolId),
        CONSTRAINT FK_RolPermiso_Permiso FOREIGN KEY (PermisoId) REFERENCES dbo.Permiso(PermisoId),
        CONSTRAINT FK_RolPermiso_AsignadoPor FOREIGN KEY (AsignadoPorUsuarioId) REFERENCES dbo.Usuario(UsuarioId)
    );
END;
GO

IF OBJECT_ID(N'dbo.Sesion', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Sesion
    (
        SesionId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_Sesion PRIMARY KEY,
        SesionHash varbinary(64) NOT NULL,
        UsuarioId int NOT NULL,
        VersionSeguridad int NOT NULL,
        MinutosInactividad smallint NOT NULL CONSTRAINT DF_Sesion_MinutosInactividad DEFAULT (30),
        CreadaUtc datetime2(3) NOT NULL CONSTRAINT DF_Sesion_CreadaUtc DEFAULT (SYSUTCDATETIME()),
        UltimaActividadUtc datetime2(3) NOT NULL CONSTRAINT DF_Sesion_UltimaActividadUtc DEFAULT (SYSUTCDATETIME()),
        ExpiraInactividadUtc datetime2(3) NOT NULL,
        ExpiraAbsolutaUtc datetime2(3) NOT NULL,
        RevocadaUtc datetime2(3) NULL,
        DireccionIP varchar(45) NULL,
        AgenteUsuario nvarchar(300) NULL,
        CorrelationId uniqueidentifier NULL,
        CONSTRAINT UQ_Sesion_Hash UNIQUE (SesionHash),
        CONSTRAINT FK_Sesion_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_Sesion_Hash CHECK (DATALENGTH(SesionHash) = 64),
        CONSTRAINT CK_Sesion_MinutosInactividad CHECK (MinutosInactividad BETWEEN 5 AND 1440),
        CONSTRAINT CK_Sesion_Expiraciones CHECK (ExpiraInactividadUtc <= ExpiraAbsolutaUtc)
    );
END;
GO

IF OBJECT_ID(N'dbo.TokenRecuperacion', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenRecuperacion
    (
        TokenRecuperacionId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_TokenRecuperacion PRIMARY KEY,
        UsuarioId int NOT NULL,
        TokenHash varbinary(64) NOT NULL,
        CreadoUtc datetime2(3) NOT NULL CONSTRAINT DF_TokenRecuperacion_CreadoUtc DEFAULT (SYSUTCDATETIME()),
        ExpiraUtc datetime2(3) NOT NULL,
        UsadoUtc datetime2(3) NULL,
        RevocadoUtc datetime2(3) NULL,
        DireccionIP varchar(45) NULL,
        CorrelationId uniqueidentifier NULL,
        CONSTRAINT UQ_TokenRecuperacion_Hash UNIQUE (TokenHash),
        CONSTRAINT FK_TokenRecuperacion_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_TokenRecuperacion_Hash CHECK (DATALENGTH(TokenHash) = 64),
        CONSTRAINT CK_TokenRecuperacion_Expira CHECK (ExpiraUtc > CreadoUtc)
    );
END;
GO

IF OBJECT_ID(N'dbo.PreferenciaUsuario', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PreferenciaUsuario
    (
        UsuarioId int NOT NULL CONSTRAINT PK_PreferenciaUsuario PRIMARY KEY,
        Tema varchar(10) NOT NULL CONSTRAINT DF_PreferenciaUsuario_Tema DEFAULT ('sistema'),
        ActualizadoUtc datetime2(3) NOT NULL CONSTRAINT DF_PreferenciaUsuario_ActualizadoUtc DEFAULT (SYSUTCDATETIME()),
        VersionFila rowversion NOT NULL,
        CONSTRAINT FK_PreferenciaUsuario_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_PreferenciaUsuario_Tema CHECK (Tema IN ('claro', 'oscuro', 'sistema'))
    );
END;
GO

IF OBJECT_ID(N'dbo.UnidadMedida', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UnidadMedida
    (
        Codigo varchar(20) COLLATE Latin1_General_100_CI_AI NOT NULL CONSTRAINT PK_UnidadMedida PRIMARY KEY,
        Nombre nvarchar(80) NOT NULL,
        Activo bit NOT NULL CONSTRAINT DF_UnidadMedida_Activo DEFAULT (1)
    );
END;
GO

IF OBJECT_ID(N'dbo.ConfiguracionSistema', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ConfiguracionSistema
    (
        ConfiguracionId tinyint NOT NULL CONSTRAINT PK_ConfiguracionSistema PRIMARY KEY,
        MonedaCodigo char(3) NOT NULL,
        ZonaHorariaIana nvarchar(64) NOT NULL,
        ZonaHorariaSql sysname NOT NULL,
        TasaIVA decimal(9,6) NOT NULL,
        ActualizadoUtc datetime2(3) NOT NULL CONSTRAINT DF_ConfiguracionSistema_ActualizadoUtc DEFAULT (SYSUTCDATETIME()),
        VersionFila rowversion NOT NULL,
        CONSTRAINT CK_ConfiguracionSistema_Unica CHECK (ConfiguracionId = 1),
        CONSTRAINT CK_ConfiguracionSistema_Moneda CHECK
            (MonedaCodigo NOT LIKE '%[^A-Z]%' COLLATE Latin1_General_100_BIN2),
        CONSTRAINT CK_ConfiguracionSistema_TasaIVA CHECK (TasaIVA BETWEEN 0 AND 1)
    );
END;
GO

IF OBJECT_ID(N'dbo.Cliente', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Cliente
    (
        ClienteId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cliente PRIMARY KEY,
        Identificador varchar(30) COLLATE Latin1_General_100_CI_AI NOT NULL,
        Nombre nvarchar(120) NOT NULL,
        Correo nvarchar(254) NULL,
        Telefono nvarchar(30) NULL,
        Activo bit NOT NULL CONSTRAINT DF_Cliente_Activo DEFAULT (1),
        CreadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Cliente_CreadoUtc DEFAULT (SYSUTCDATETIME()),
        ActualizadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Cliente_ActualizadoUtc DEFAULT (SYSUTCDATETIME()),
        VersionFila rowversion NOT NULL,
        CONSTRAINT UQ_Cliente_Identificador UNIQUE (Identificador),
        CONSTRAINT CK_Cliente_Identificador CHECK (LEN(Identificador) BETWEEN 1 AND 30),
        CONSTRAINT CK_Cliente_Nombre CHECK (LEN(Nombre) BETWEEN 2 AND 120)
    );
END;
GO

IF OBJECT_ID(N'dbo.Producto', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Producto
    (
        ProductoId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Producto PRIMARY KEY,
        Codigo varchar(30) COLLATE Latin1_General_100_CI_AI NOT NULL,
        Descripcion nvarchar(160) NOT NULL,
        Unidad varchar(20) COLLATE Latin1_General_100_CI_AI NOT NULL,
        Precio decimal(19,2) NOT NULL,
        Stock int NOT NULL CONSTRAINT DF_Producto_Stock DEFAULT (0),
        Activo bit NOT NULL CONSTRAINT DF_Producto_Activo DEFAULT (1),
        CreadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Producto_CreadoUtc DEFAULT (SYSUTCDATETIME()),
        ActualizadoUtc datetime2(3) NOT NULL CONSTRAINT DF_Producto_ActualizadoUtc DEFAULT (SYSUTCDATETIME()),
        VersionFila rowversion NOT NULL,
        CONSTRAINT UQ_Producto_Codigo UNIQUE (Codigo),
        CONSTRAINT FK_Producto_Unidad FOREIGN KEY (Unidad) REFERENCES dbo.UnidadMedida(Codigo),
        CONSTRAINT CK_Producto_Codigo CHECK (LEN(Codigo) BETWEEN 1 AND 30),
        CONSTRAINT CK_Producto_Descripcion CHECK (LEN(Descripcion) BETWEEN 2 AND 160),
        CONSTRAINT CK_Producto_Precio CHECK (Precio BETWEEN 0.01 AND 999999.99),
        CONSTRAINT CK_Producto_Stock CHECK (Stock BETWEEN 0 AND 2147483647)
    );
END;
GO

IF OBJECT_ID(N'dbo.MovimientoInventario', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MovimientoInventario
    (
        MovimientoInventarioId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_MovimientoInventario PRIMARY KEY,
        ProductoId int NOT NULL,
        Variacion int NOT NULL,
        StockAnterior int NOT NULL,
        StockNuevo int NOT NULL,
        Motivo nvarchar(250) NOT NULL,
        UsuarioId int NOT NULL,
        FechaUtc datetime2(3) NOT NULL CONSTRAINT DF_MovimientoInventario_FechaUtc DEFAULT (SYSUTCDATETIME()),
        CorrelationId uniqueidentifier NULL,
        CONSTRAINT FK_MovimientoInventario_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto(ProductoId),
        CONSTRAINT FK_MovimientoInventario_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_MovimientoInventario_Variacion CHECK (Variacion <> 0),
        CONSTRAINT CK_MovimientoInventario_Motivo CHECK (LEN(Motivo) BETWEEN 10 AND 250),
        CONSTRAINT CK_MovimientoInventario_Stock CHECK (StockAnterior >= 0 AND StockNuevo >= 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.SeqNumeroFactura', N'SO') IS NULL
    CREATE SEQUENCE dbo.SeqNumeroFactura AS bigint START WITH 1 INCREMENT BY 1 CACHE 50;
GO

IF OBJECT_ID(N'dbo.Factura', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Factura
    (
        FacturaId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_Factura PRIMARY KEY,
        Numero bigint NOT NULL CONSTRAINT DF_Factura_Numero DEFAULT (NEXT VALUE FOR dbo.SeqNumeroFactura),
        Estado varchar(20) NOT NULL CONSTRAINT DF_Factura_Estado DEFAULT ('Confirmada'),
        ClienteId int NOT NULL,
        ClienteIdentificador varchar(30) NOT NULL,
        ClienteNombre nvarchar(120) NOT NULL,
        UsuarioId int NOT NULL,
        CajeroNombre nvarchar(120) NOT NULL,
        FechaUtc datetime2(3) NOT NULL CONSTRAINT DF_Factura_FechaUtc DEFAULT (SYSUTCDATETIME()),
        Moneda char(3) NOT NULL CONSTRAINT DF_Factura_Moneda DEFAULT ('GTQ'),
        TasaIVA decimal(9,6) NOT NULL CONSTRAINT DF_Factura_TasaIVA DEFAULT (0.120000),
        Subtotal decimal(19,2) NOT NULL,
        IVA decimal(19,2) NOT NULL,
        Total decimal(19,2) NOT NULL,
        ClaveIdempotencia uniqueidentifier NOT NULL,
        HuellaContenido varbinary(32) NOT NULL,
        CorrelationId uniqueidentifier NULL,
        CONSTRAINT UQ_Factura_Numero UNIQUE (Numero),
        CONSTRAINT UQ_Factura_Usuario_Clave UNIQUE (UsuarioId, ClaveIdempotencia),
        CONSTRAINT FK_Factura_Cliente FOREIGN KEY (ClienteId) REFERENCES dbo.Cliente(ClienteId),
        CONSTRAINT FK_Factura_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_Factura_Estado CHECK (Estado = 'Confirmada'),
        CONSTRAINT CK_Factura_Moneda CHECK (Moneda NOT LIKE '%[^A-Z]%' COLLATE Latin1_General_100_BIN2),
        CONSTRAINT CK_Factura_Importes CHECK (Subtotal >= 0 AND IVA >= 0 AND Total = Subtotal + IVA),
        CONSTRAINT CK_Factura_Huella CHECK (DATALENGTH(HuellaContenido) = 32)
    );
END;
GO

IF OBJECT_ID(N'dbo.Detalle_Factura', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Detalle_Factura
    (
        DetalleFacturaId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_DetalleFactura PRIMARY KEY,
        FacturaId bigint NOT NULL,
        ProductoId int NOT NULL,
        ProductoCodigo varchar(30) NOT NULL,
        ProductoDescripcion nvarchar(160) NOT NULL,
        Unidad varchar(20) NOT NULL,
        Cantidad int NOT NULL,
        PrecioUnitario decimal(19,2) NOT NULL,
        Importe decimal(19,2) NOT NULL,
        CONSTRAINT UQ_DetalleFactura_Factura_Producto UNIQUE (FacturaId, ProductoId),
        CONSTRAINT FK_DetalleFactura_Factura FOREIGN KEY (FacturaId) REFERENCES dbo.Factura(FacturaId),
        CONSTRAINT FK_DetalleFactura_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto(ProductoId),
        CONSTRAINT CK_DetalleFactura_Cantidad CHECK (Cantidad BETWEEN 1 AND 9999),
        CONSTRAINT CK_DetalleFactura_Importes CHECK
        (
            PrecioUnitario BETWEEN 0.01 AND 999999.99
            AND Importe = CONVERT(decimal(19,2), Cantidad * PrecioUnitario)
        )
    );
END;
GO

IF OBJECT_ID(N'dbo.MovimientoCaja', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MovimientoCaja
    (
        MovimientoCajaId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_MovimientoCaja PRIMARY KEY,
        FacturaId bigint NOT NULL,
        Tipo varchar(20) NOT NULL CONSTRAINT DF_MovimientoCaja_Tipo DEFAULT ('INGRESO_VENTA'),
        Importe decimal(19,2) NOT NULL,
        Moneda char(3) NOT NULL,
        UsuarioId int NOT NULL,
        FechaUtc datetime2(3) NOT NULL CONSTRAINT DF_MovimientoCaja_FechaUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_MovimientoCaja_Factura UNIQUE (FacturaId),
        CONSTRAINT FK_MovimientoCaja_Factura FOREIGN KEY (FacturaId) REFERENCES dbo.Factura(FacturaId),
        CONSTRAINT FK_MovimientoCaja_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_MovimientoCaja_Tipo CHECK (Tipo = 'INGRESO_VENTA'),
        CONSTRAINT CK_MovimientoCaja_Importe CHECK (Importe > 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.Bitacora_Acceso', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Bitacora_Acceso
    (
        BitacoraAccesoId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_BitacoraAcceso PRIMARY KEY,
        FechaUtc datetime2(3) NOT NULL CONSTRAINT DF_BitacoraAcceso_FechaUtc DEFAULT (SYSUTCDATETIME()),
        NombreUsuarioIntentado varchar(254) NULL,
        UsuarioId int NULL,
        Resultado varchar(30) NOT NULL,
        MotivoInterno nvarchar(250) NULL,
        DireccionIP varchar(45) NULL,
        AgenteUsuario nvarchar(300) NULL,
        PrincipalSql nvarchar(128) NOT NULL CONSTRAINT DF_BitacoraAcceso_Principal DEFAULT (SUSER_SNAME()),
        HostName nvarchar(128) NULL CONSTRAINT DF_BitacoraAcceso_Host DEFAULT (HOST_NAME()),
        AppName nvarchar(128) NULL CONSTRAINT DF_BitacoraAcceso_App DEFAULT (APP_NAME()),
        CorrelationId uniqueidentifier NULL,
        CONSTRAINT FK_BitacoraAcceso_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_BitacoraAcceso_Resultado CHECK (Resultado IN ('EXITOSO', 'RECHAZADO', 'LIMITADO', 'RECUPERACION'))
    );
END;
GO

IF OBJECT_ID(N'dbo.Bitacora_Transacciones', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Bitacora_Transacciones
    (
        BitacoraTransaccionId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_BitacoraTransacciones PRIMARY KEY,
        FechaUtc datetime2(3) NOT NULL CONSTRAINT DF_BitacoraTransacciones_FechaUtc DEFAULT (SYSUTCDATETIME()),
        Tabla sysname NOT NULL,
        Operacion varchar(10) NOT NULL,
        RegistroId nvarchar(200) NOT NULL,
        UsuarioAplicacionId int NULL,
        UsuarioAplicacion varchar(50) NULL,
        PrincipalSql nvarchar(128) NOT NULL CONSTRAINT DF_BitacoraTransacciones_Principal DEFAULT (SUSER_SNAME()),
        HostName nvarchar(128) NULL CONSTRAINT DF_BitacoraTransacciones_Host DEFAULT (HOST_NAME()),
        AppName nvarchar(128) NULL CONSTRAINT DF_BitacoraTransacciones_App DEFAULT (APP_NAME()),
        DireccionIP varchar(45) NULL,
        CorrelationId uniqueidentifier NULL,
        Motivo nvarchar(250) NULL,
        ValoresAnteriores nvarchar(max) NULL,
        ValoresNuevos nvarchar(max) NULL,
        CONSTRAINT CK_BitacoraTransacciones_Operacion CHECK (Operacion IN ('INSERT', 'UPDATE', 'DELETE')),
        CONSTRAINT CK_BitacoraTransacciones_AnteriorJson CHECK (ValoresAnteriores IS NULL OR ISJSON(ValoresAnteriores) = 1),
        CONSTRAINT CK_BitacoraTransacciones_NuevoJson CHECK (ValoresNuevos IS NULL OR ISJSON(ValoresNuevos) = 1)
    );
END;
GO

IF OBJECT_ID(N'dbo.Bitacora_DDL', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Bitacora_DDL
    (
        BitacoraDDLId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_BitacoraDDL PRIMARY KEY,
        FechaUtc datetime2(3) NOT NULL CONSTRAINT DF_BitacoraDDL_FechaUtc DEFAULT (SYSUTCDATETIME()),
        TipoEvento sysname NOT NULL,
        TipoObjeto sysname NULL,
        NombreObjeto sysname NULL,
        Esquema sysname NULL,
        Comando nvarchar(max) NULL,
        PrincipalSql nvarchar(128) NOT NULL,
        UsuarioAplicacion varchar(50) NULL,
        HostName nvarchar(128) NULL,
        AppName nvarchar(128) NULL,
        CorrelationId uniqueidentifier NULL,
        DatosEvento xml NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.Bitacora_Incidente', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Bitacora_Incidente
    (
        BitacoraIncidenteId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_BitacoraIncidente PRIMARY KEY,
        FechaUtc datetime2(3) NOT NULL CONSTRAINT DF_BitacoraIncidente_FechaUtc DEFAULT (SYSUTCDATETIME()),
        Operacion varchar(80) NOT NULL,
        UsuarioId int NULL,
        CorrelationId uniqueidentifier NULL,
        NumeroError int NULL,
        MensajeSanitizado nvarchar(500) NOT NULL,
        PrincipalSql nvarchar(128) NOT NULL CONSTRAINT DF_BitacoraIncidente_Principal DEFAULT (SUSER_SNAME()),
        HostName nvarchar(128) NULL CONSTRAINT DF_BitacoraIncidente_Host DEFAULT (HOST_NAME()),
        AppName nvarchar(128) NULL CONSTRAINT DF_BitacoraIncidente_App DEFAULT (APP_NAME())
    );
END;
GO

IF TYPE_ID(N'dbo.TVP_DetalleFactura') IS NULL
    EXEC(N'CREATE TYPE dbo.TVP_DetalleFactura AS TABLE
    (
        ProductoId int NOT NULL,
        Cantidad int NOT NULL,
        PRIMARY KEY (ProductoId),
        CHECK (Cantidad BETWEEN 1 AND 9999)
    );');
GO

IF TYPE_ID(N'dbo.TVP_IdEntero') IS NULL
    EXEC(N'CREATE TYPE dbo.TVP_IdEntero AS TABLE
    (
        Id int NOT NULL PRIMARY KEY
    );');
GO

IF TYPE_ID(N'dbo.TVP_ListaEnteros') IS NULL
    EXEC(N'CREATE TYPE dbo.TVP_ListaEnteros AS TABLE
    (
        Id int NOT NULL PRIMARY KEY
    );');
GO

IF TYPE_ID(N'dbo.TVP_CodigosPermiso') IS NULL
    EXEC(N'CREATE TYPE dbo.TVP_CodigosPermiso AS TABLE
    (
        Codigo varchar(50) COLLATE Latin1_General_100_CI_AI NOT NULL PRIMARY KEY
    );');
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Sesion') AND name = N'IX_Sesion_Usuario_Vigencia')
    CREATE INDEX IX_Sesion_Usuario_Vigencia ON dbo.Sesion(UsuarioId, RevocadaUtc, ExpiraInactividadUtc, ExpiraAbsolutaUtc);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.TokenRecuperacion') AND name = N'IX_TokenRecuperacion_Usuario_Vigencia')
    CREATE INDEX IX_TokenRecuperacion_Usuario_Vigencia ON dbo.TokenRecuperacion(UsuarioId, UsadoUtc, RevocadoUtc, ExpiraUtc);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Producto') AND name = N'IX_Producto_Descripcion')
    CREATE INDEX IX_Producto_Descripcion ON dbo.Producto(Descripcion, ProductoId) INCLUDE (Codigo, Unidad, Precio, Stock, Activo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Cliente') AND name = N'IX_Cliente_Nombre')
    CREATE INDEX IX_Cliente_Nombre ON dbo.Cliente(Nombre, ClienteId) INCLUDE (Identificador, Correo, Telefono, Activo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Factura') AND name = N'IX_Factura_Fecha')
    CREATE INDEX IX_Factura_Fecha ON dbo.Factura(FechaUtc DESC, FacturaId DESC) INCLUDE (Numero, ClienteId, UsuarioId, Subtotal, IVA, Total, Moneda);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Factura') AND name = N'IX_Factura_Usuario_Fecha')
    CREATE INDEX IX_Factura_Usuario_Fecha ON dbo.Factura(UsuarioId, FechaUtc DESC, FacturaId DESC) INCLUDE (Numero, ClienteNombre, Total, Moneda);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Bitacora_Acceso') AND name = N'IX_BitacoraAcceso_Fecha')
    CREATE INDEX IX_BitacoraAcceso_Fecha ON dbo.Bitacora_Acceso(FechaUtc DESC, BitacoraAccesoId DESC) INCLUDE (UsuarioId, Resultado, DireccionIP, CorrelationId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Bitacora_Transacciones') AND name = N'IX_BitacoraTransacciones_Fecha')
    CREATE INDEX IX_BitacoraTransacciones_Fecha ON dbo.Bitacora_Transacciones(FechaUtc DESC, BitacoraTransaccionId DESC) INCLUDE (Tabla, Operacion, UsuarioAplicacionId, CorrelationId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Bitacora_DDL') AND name = N'IX_BitacoraDDL_Fecha')
    CREATE INDEX IX_BitacoraDDL_Fecha ON dbo.Bitacora_DDL(FechaUtc DESC, BitacoraDDLId DESC) INCLUDE (TipoEvento, TipoObjeto, NombreObjeto, PrincipalSql);
GO

DECLARE @Permisos TABLE
(
    Codigo varchar(60) COLLATE Latin1_General_100_CI_AI,
    Nombre nvarchar(120),
    Modulo varchar(40)
);
INSERT @Permisos (Codigo, Nombre, Modulo)
VALUES
    ('VENTAS_CREAR', N'Procesar ventas y consultar facturas propias', 'VENTAS'),
    ('AUDITORIA_LEER', N'Consultar bitacoras y auditoria', 'AUDITORIA'),
    ('ROLES_GESTIONAR', N'Gestionar roles y permisos', 'SEGURIDAD'),
    ('PRODUCTOS_GESTIONAR', N'Gestionar productos e inventario', 'CATALOGOS'),
    ('CLIENTES_GESTIONAR', N'Gestionar clientes', 'CATALOGOS'),
    ('REPORTES_LEER', N'Consultar reportes y todas las facturas', 'REPORTES'),
    ('USUARIOS_GESTIONAR', N'Gestionar usuarios y sus roles', 'SEGURIDAD');

UPDATE p
SET Nombre = s.Nombre, Modulo = s.Modulo, Activo = 1, ActualizadoUtc = SYSUTCDATETIME()
FROM dbo.Permiso AS p
JOIN @Permisos AS s ON s.Codigo = p.Codigo;

INSERT dbo.Permiso (Codigo, Nombre, Modulo)
SELECT s.Codigo, s.Nombre, s.Modulo
FROM @Permisos AS s
WHERE NOT EXISTS (SELECT 1 FROM dbo.Permiso AS p WHERE p.Codigo = s.Codigo);

DECLARE @Unidades TABLE
(
    Codigo varchar(20) COLLATE Latin1_General_100_CI_AI,
    Nombre nvarchar(80)
);
INSERT @Unidades VALUES ('UNIDAD', N'Unidad'), ('SERVICIO', N'Servicio'), ('CAJA', N'Caja'), ('PAQUETE', N'Paquete');
UPDATE u SET Nombre = s.Nombre, Activo = 1 FROM dbo.UnidadMedida u JOIN @Unidades s ON s.Codigo = u.Codigo;
INSERT dbo.UnidadMedida (Codigo, Nombre)
SELECT s.Codigo, s.Nombre FROM @Unidades s
WHERE NOT EXISTS (SELECT 1 FROM dbo.UnidadMedida u WHERE u.Codigo = s.Codigo);

IF NOT EXISTS (SELECT 1 FROM dbo.ConfiguracionSistema WHERE ConfiguracionId = 1)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = N'Central America Standard Time')
        THROW 51006, N'La zona SQL Central America Standard Time no esta disponible.', 1;
    INSERT dbo.ConfiguracionSistema
        (ConfiguracionId, MonedaCodigo, ZonaHorariaIana, ZonaHorariaSql, TasaIVA)
    VALUES
        (1, 'GTQ', N'America/Guatemala', N'Central America Standard Time', 0.120000);
END;
GO
/* ===== FIN: database\01_schema.sql ===== */

/* ===== INICIO: database\02_functions.sql ===== */
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
/* ===== FIN: database\02_functions.sql ===== */

/* ===== INICIO: database\03_security.sql ===== */
USE [$(DatabaseName)];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_LimpiarContextoAuditoria
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = NULL;
    EXEC sys.sp_set_session_context @key = N'UsuarioAplicacion', @value = NULL;
    EXEC sys.sp_set_session_context @key = N'DireccionIP', @value = NULL;
    EXEC sys.sp_set_session_context @key = N'CorrelationId', @value = NULL;
    EXEC sys.sp_set_session_context @key = N'MotivoAuditoria', @value = NULL;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RegistrarAcceso
    @NombreUsuarioIntentado varchar(254) = NULL,
    @UsuarioId int = NULL,
    @Resultado varchar(30),
    @MotivoInterno nvarchar(250) = NULL,
    @DireccionIP varchar(45) = NULL,
    @AgenteUsuario nvarchar(300) = NULL,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Resultado NOT IN ('EXITOSO', 'RECHAZADO', 'LIMITADO', 'RECUPERACION')
        THROW 51006, N'Resultado de acceso no valido.', 1;

    INSERT dbo.Bitacora_Acceso
    (
        NombreUsuarioIntentado, UsuarioId, Resultado, MotivoInterno,
        DireccionIP, AgenteUsuario, CorrelationId
    )
    VALUES
    (
        LEFT(@NombreUsuarioIntentado, 254), @UsuarioId, @Resultado, LEFT(@MotivoInterno, 250),
        @DireccionIP, LEFT(@AgenteUsuario, 300), @CorrelationId
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ResolverSesion
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL,
    @PermisoRequerido varchar(60) = NULL,
    @PermitirCambioObligatorio bit = 0,
    @ActualizarActividad bit = 1,
    @UsuarioId int OUTPUT,
    @NombreUsuario varchar(50) OUTPUT,
    @NombreVisible nvarchar(120) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_LimpiarContextoAuditoria;

    DECLARE @Ahora datetime2(3) = SYSUTCDATETIME();
    DECLARE @SesionId bigint;
    DECLARE @MinutosInactividad smallint;
    DECLARE @ExpiraAbsolutaUtc datetime2(3);
    DECLARE @DebeCambiar bit;

    SELECT
        @SesionId = s.SesionId,
        @UsuarioId = u.UsuarioId,
        @NombreUsuario = u.NombreUsuario,
        @NombreVisible = u.NombreVisible,
        @MinutosInactividad = s.MinutosInactividad,
        @ExpiraAbsolutaUtc = s.ExpiraAbsolutaUtc,
        @DebeCambiar = u.DebeCambiarPassword
    FROM dbo.Sesion AS s
    JOIN dbo.Usuario AS u ON u.UsuarioId = s.UsuarioId
    WHERE s.SesionHash = @SesionHash
      AND s.RevocadaUtc IS NULL
      AND s.ExpiraInactividadUtc > @Ahora
      AND s.ExpiraAbsolutaUtc > @Ahora
      AND s.VersionSeguridad = u.VersionSeguridad
      AND u.Activo = 1;

    IF @SesionId IS NULL
        THROW 51001, N'La sesion no existe o ha vencido.', 1;

    IF @DebeCambiar = 1 AND @PermitirCambioObligatorio = 0
        THROW 51007, N'Debe cambiar la contrasena antes de continuar.', 1;

    IF @PermisoRequerido IS NOT NULL
       AND dbo.fn_TienePermiso(@UsuarioId, @PermisoRequerido) = 0
        THROW 51002, N'Permiso insuficiente.', 1;

    IF @ActualizarActividad = 1
    BEGIN
        UPDATE dbo.Sesion
        SET UltimaActividadUtc = @Ahora,
            ExpiraInactividadUtc =
                CASE
                    WHEN DATEADD(minute, @MinutosInactividad, @Ahora) < @ExpiraAbsolutaUtc
                    THEN DATEADD(minute, @MinutosInactividad, @Ahora)
                    ELSE @ExpiraAbsolutaUtc
                END,
            DireccionIP = COALESCE(@DireccionIP, DireccionIP)
        WHERE SesionId = @SesionId
          AND RevocadaUtc IS NULL;
    END;

    EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId;
    EXEC sys.sp_set_session_context @key = N'UsuarioAplicacion', @value = @NombreUsuario;
    EXEC sys.sp_set_session_context @key = N'DireccionIP', @value = @DireccionIP;
    EXEC sys.sp_set_session_context @key = N'CorrelationId', @value = @CorrelationId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ObtenerPermisosUsuario
    @UsuarioId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT p.Codigo AS code, p.Nombre AS name, p.Modulo AS module
    FROM dbo.Usuario_Rol ur
    JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
    JOIN dbo.Rol_Permiso rp ON rp.RolId = r.RolId
    JOIN dbo.Permiso p ON p.PermisoId = rp.PermisoId AND p.Activo = 1
    WHERE ur.UsuarioId = @UsuarioId
    ORDER BY p.Codigo;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AutenticarUsuario
    @NombreUsuario varchar(50),
    @Contrasena nvarchar(128),
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @AgenteUsuario nvarchar(300) = NULL,
    @MinutosInactividad smallint = 30,
    @HorasAbsolutas tinyint = 8,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;

    IF DATALENGTH(@SesionHash) <> 64 OR @MinutosInactividad NOT BETWEEN 5 AND 1440
       OR @HorasAbsolutas NOT BETWEEN 1 AND 24
        THROW 51006, N'Parametros de sesion no validos.', 1;

    DECLARE @Ahora datetime2(3) = SYSUTCDATETIME();
    DECLARE @Fallos int;
    SELECT @Fallos = COUNT_BIG(*)
    FROM dbo.Bitacora_Acceso
    WHERE FechaUtc >= DATEADD(minute, -15, @Ahora)
      AND Resultado IN ('RECHAZADO', 'LIMITADO')
      AND
      (
          NombreUsuarioIntentado = @NombreUsuario
          OR (@DireccionIP IS NOT NULL AND DireccionIP = @DireccionIP)
      );

    IF @Fallos >= 5
    BEGIN
        EXEC dbo.sp_RegistrarAcceso @NombreUsuario, NULL, 'LIMITADO', N'Limite de intentos alcanzado',
            @DireccionIP, @AgenteUsuario, @CorrelationId;
        THROW 51005, N'Demasiados intentos.', 1;
    END;

    DECLARE @UsuarioId int;
    DECLARE @HashGuardado varbinary(64);
    DECLARE @Salt varbinary(32);
    DECLARE @Activo bit;
    DECLARE @NombreVisible nvarchar(120);
    DECLARE @VersionSeguridad int;
    DECLARE @DebeCambiar bit;

    SELECT
        @UsuarioId = UsuarioId,
        @HashGuardado = PasswordHash,
        @Salt = PasswordSalt,
        @Activo = Activo,
        @NombreVisible = NombreVisible,
        @VersionSeguridad = VersionSeguridad,
        @DebeCambiar = DebeCambiarPassword
    FROM dbo.Usuario
    WHERE NombreUsuario = @NombreUsuario;

    DECLARE @HashCalculado varbinary(64) = HASHBYTES
    (
        'SHA2_512',
        COALESCE(@Salt, CONVERT(varbinary(32), 0x5E5A8B22F77E01F9CDE4A0A4B584F5B5C7D5F47D5A65940A35D94AE44C365B33))
        + CONVERT(varbinary(256), @Contrasena)
    );

    IF @UsuarioId IS NULL OR @Activo = 0 OR @HashCalculado <> @HashGuardado
    BEGIN
        DECLARE @MotivoRechazo nvarchar(250) =
            CASE WHEN @UsuarioId IS NULL THEN N'Usuario inexistente'
                 WHEN @Activo = 0 THEN N'Cuenta inactiva'
                 ELSE N'Contrasena incorrecta' END;
        EXEC dbo.sp_RegistrarAcceso @NombreUsuario, @UsuarioId, 'RECHAZADO', @MotivoRechazo,
            @DireccionIP, @AgenteUsuario, @CorrelationId;
        THROW 51011, N'Credenciales invalidas.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT dbo.Sesion
        (
            SesionHash, UsuarioId, VersionSeguridad, MinutosInactividad,
            ExpiraInactividadUtc, ExpiraAbsolutaUtc, DireccionIP, AgenteUsuario, CorrelationId
        )
        VALUES
        (
            @SesionHash, @UsuarioId, @VersionSeguridad, @MinutosInactividad,
            DATEADD(minute, @MinutosInactividad, @Ahora), DATEADD(hour, @HorasAbsolutas, @Ahora),
            @DireccionIP, @AgenteUsuario, @CorrelationId
        );

        IF NOT EXISTS (SELECT 1 FROM dbo.PreferenciaUsuario WHERE UsuarioId = @UsuarioId)
            INSERT dbo.PreferenciaUsuario (UsuarioId, Tema) VALUES (@UsuarioId, 'sistema');

        EXEC dbo.sp_RegistrarAcceso @NombreUsuario, @UsuarioId, 'EXITOSO', N'Autenticacion correcta',
            @DireccionIP, @AgenteUsuario, @CorrelationId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT
        u.UsuarioId AS userId,
        u.NombreUsuario AS username,
        u.NombreVisible AS displayName,
        u.CorreoRecuperacion AS email,
        u.DebeCambiarPassword AS mustChangePassword,
        COALESCE(pu.Tema, 'sistema') AS theme,
        u.VersionSeguridad AS version,
        DATEADD(minute, @MinutosInactividad, @Ahora) AS sessionExpiresAt,
        DATEADD(hour, @HorasAbsolutas, @Ahora) AS absoluteExpiresAt
    FROM dbo.Usuario u
    LEFT JOIN dbo.PreferenciaUsuario pu ON pu.UsuarioId = u.UsuarioId
    WHERE u.UsuarioId = @UsuarioId;

    EXEC dbo.sp_ObtenerPermisosUsuario @UsuarioId;

    SELECT r.Nombre AS name
    FROM dbo.Usuario_Rol ur
    JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
    WHERE ur.UsuarioId = @UsuarioId
    ORDER BY r.Nombre;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ValidarSesionApi
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @ActualizarActividad bit = 1,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int, @NombreUsuario varchar(50), @NombreVisible nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, NULL, 1,
            @ActualizarActividad, @UsuarioId OUTPUT, @NombreUsuario OUTPUT, @NombreVisible OUTPUT;

        SELECT
            u.UsuarioId AS userId,
            u.NombreUsuario AS username,
            u.NombreVisible AS displayName,
            u.CorreoRecuperacion AS email,
            u.DebeCambiarPassword AS mustChangePassword,
            COALESCE(p.Tema, 'sistema') AS theme,
            u.VersionSeguridad AS version,
            s.ExpiraInactividadUtc AS sessionExpiresAt,
            s.ExpiraAbsolutaUtc AS absoluteExpiresAt
        FROM dbo.Usuario u
        JOIN dbo.Sesion s ON s.SesionHash = @SesionHash AND s.UsuarioId = u.UsuarioId
        LEFT JOIN dbo.PreferenciaUsuario p ON p.UsuarioId = u.UsuarioId
        WHERE u.UsuarioId = @UsuarioId;

        EXEC dbo.sp_ObtenerPermisosUsuario @UsuarioId;

        SELECT r.Nombre AS name
        FROM dbo.Usuario_Rol ur
        JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
        WHERE ur.UsuarioId = @UsuarioId
        ORDER BY r.Nombre;

        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CerrarSesion
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int, @NombreUsuario varchar(50), @NombreVisible nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, NULL, 1, 0,
            @UsuarioId OUTPUT, @NombreUsuario OUTPUT, @NombreVisible OUTPUT;
        UPDATE dbo.Sesion SET RevocadaUtc = COALESCE(RevocadaUtc, SYSUTCDATETIME())
        WHERE SesionHash = @SesionHash;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarPerfil
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int, @NombreUsuario varchar(50), @NombreVisible nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, NULL, 0, 1,
            @UsuarioId OUTPUT, @NombreUsuario OUTPUT, @NombreVisible OUTPUT;

        SELECT u.UsuarioId AS id, u.NombreUsuario AS username, u.NombreVisible AS displayName,
               u.CorreoRecuperacion AS email, u.Activo AS active,
               COALESCE(p.Tema, 'sistema') AS theme, u.CreadoUtc AS createdAt
        FROM dbo.Usuario u
        LEFT JOIN dbo.PreferenciaUsuario p ON p.UsuarioId = u.UsuarioId
        WHERE u.UsuarioId = @UsuarioId;
        EXEC dbo.sp_ObtenerPermisosUsuario @UsuarioId;
        SELECT r.RolId AS id, r.Nombre AS name
        FROM dbo.Usuario_Rol ur JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
        WHERE ur.UsuarioId = @UsuarioId ORDER BY r.Nombre;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ObtenerPreferenciasUsuario
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int, @NombreUsuario varchar(50), @NombreVisible nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, NULL, 1, 0,
            @UsuarioId OUTPUT, @NombreUsuario OUTPUT, @NombreVisible OUTPUT;
        SELECT COALESCE(p.Tema, 'sistema') AS theme, p.ActualizadoUtc AS updatedAt
        FROM dbo.Usuario u LEFT JOIN dbo.PreferenciaUsuario p ON p.UsuarioId = u.UsuarioId
        WHERE u.UsuarioId = @UsuarioId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GuardarPreferenciasUsuario
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL,
    @Tema varchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Tema NOT IN ('claro', 'oscuro', 'sistema') THROW 51006, N'Tema no valido.', 1;
    DECLARE @UsuarioId int, @NombreUsuario varchar(50), @NombreVisible nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, NULL, 0, 1,
            @UsuarioId OUTPUT, @NombreUsuario OUTPUT, @NombreVisible OUTPUT;
        UPDATE dbo.PreferenciaUsuario SET Tema = @Tema, ActualizadoUtc = SYSUTCDATETIME()
        WHERE UsuarioId = @UsuarioId;
        IF @@ROWCOUNT = 0 INSERT dbo.PreferenciaUsuario (UsuarioId, Tema) VALUES (@UsuarioId, @Tema);
        SELECT Tema AS theme, ActualizadoUtc AS updatedAt FROM dbo.PreferenciaUsuario WHERE UsuarioId = @UsuarioId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CambiarPassword
    @SesionHash varbinary(64),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL,
    @ContrasenaActual nvarchar(128),
    @ContrasenaNueva nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF dbo.fn_ContrasenaCumplePolitica(@ContrasenaNueva) = 0
        THROW 51006, N'La contrasena nueva no cumple la politica.', 1;
    IF @ContrasenaActual = @ContrasenaNueva
        THROW 51006, N'La contrasena nueva debe ser distinta.', 1;

    DECLARE @UsuarioId int, @NombreUsuario varchar(50), @NombreVisible nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, NULL, 1, 1,
            @UsuarioId OUTPUT, @NombreUsuario OUTPUT, @NombreVisible OUTPUT;
        BEGIN TRANSACTION;
        DECLARE @SaltActual varbinary(32), @HashActual varbinary(64);
        SELECT @SaltActual = PasswordSalt, @HashActual = PasswordHash
        FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK) WHERE UsuarioId = @UsuarioId;
        IF HASHBYTES('SHA2_512', @SaltActual + CONVERT(varbinary(256), @ContrasenaActual)) <> @HashActual
            THROW 51011, N'Credencial actual incorrecta.', 1;

        DECLARE @NuevoSalt varbinary(32) = CRYPT_GEN_RANDOM(32);
        UPDATE dbo.Usuario
        SET PasswordSalt = @NuevoSalt,
            PasswordHash = HASHBYTES('SHA2_512', @NuevoSalt + CONVERT(varbinary(256), @ContrasenaNueva)),
            DebeCambiarPassword = 0,
            VersionSeguridad = VersionSeguridad + 1,
            UltimoCambioPasswordUtc = SYSUTCDATETIME(),
            ActualizadoUtc = SYSUTCDATETIME()
        WHERE UsuarioId = @UsuarioId;
        UPDATE dbo.Sesion SET RevocadaUtc = COALESCE(RevocadaUtc, SYSUTCDATETIME()) WHERE UsuarioId = @UsuarioId;
        UPDATE dbo.TokenRecuperacion SET RevocadoUtc = COALESCE(RevocadoUtc, SYSUTCDATETIME())
        WHERE UsuarioId = @UsuarioId AND UsadoUtc IS NULL AND RevocadoUtc IS NULL;
        COMMIT TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_SolicitarRecuperacion
    @Identidad nvarchar(254),
    @TokenHash varbinary(64),
    @MinutosVigencia tinyint = 15,
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF DATALENGTH(@TokenHash) <> 64 OR @MinutosVigencia NOT BETWEEN 5 AND 60
        THROW 51006, N'Parametros de recuperacion no validos.', 1;

    DECLARE @UsuarioId int, @Correo nvarchar(254);
    SELECT TOP (1) @UsuarioId = UsuarioId, @Correo = CorreoRecuperacion
    FROM dbo.Usuario
    WHERE Activo = 1 AND CorreoRecuperacion IS NOT NULL
      AND (NombreUsuario = CONVERT(varchar(50), @Identidad) OR CorreoRecuperacion = @Identidad);

    DECLARE @IdentidadAuditoria varchar(254) = CONVERT(varchar(254), @Identidad);
    DECLARE @MotivoRecuperacion nvarchar(250) =
        CASE WHEN @UsuarioId IS NULL THEN N'Solicitud no elegible' ELSE N'Token emitido' END;
    EXEC dbo.sp_RegistrarAcceso @IdentidadAuditoria, @UsuarioId, 'RECUPERACION', @MotivoRecuperacion,
        @DireccionIP, NULL, @CorrelationId;

    IF @UsuarioId IS NOT NULL
    BEGIN
        UPDATE dbo.TokenRecuperacion
        SET RevocadoUtc = COALESCE(RevocadoUtc, SYSUTCDATETIME())
        WHERE UsuarioId = @UsuarioId AND UsadoUtc IS NULL AND RevocadoUtc IS NULL;

        INSERT dbo.TokenRecuperacion
        (UsuarioId, TokenHash, ExpiraUtc, DireccionIP, CorrelationId)
        VALUES (@UsuarioId, @TokenHash, DATEADD(minute, @MinutosVigencia, SYSUTCDATETIME()), @DireccionIP, @CorrelationId);

        SELECT @Correo AS mailboxAddress, DATEADD(minute, @MinutosVigencia, SYSUTCDATETIME()) AS expiresAt;
    END;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ValidarTokenRecuperacion
    @TokenHash varbinary(64)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    SELECT TOP (1) tr.TokenRecuperacionId AS tokenId, tr.ExpiraUtc AS expiresAt
    FROM dbo.TokenRecuperacion tr
    JOIN dbo.Usuario u ON u.UsuarioId = tr.UsuarioId AND u.Activo = 1
    WHERE tr.TokenHash = @TokenHash AND tr.UsadoUtc IS NULL AND tr.RevocadoUtc IS NULL
      AND tr.ExpiraUtc > SYSUTCDATETIME();
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RestablecerPassword
    @TokenHash varbinary(64),
    @ContrasenaNueva nvarchar(128),
    @DireccionIP varchar(45) = NULL,
    @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF dbo.fn_ContrasenaCumplePolitica(@ContrasenaNueva) = 0
        THROW 51006, N'La contrasena nueva no cumple la politica.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @TokenId bigint, @UsuarioId int, @NombreUsuario varchar(50);
        SELECT @TokenId = tr.TokenRecuperacionId, @UsuarioId = tr.UsuarioId, @NombreUsuario = u.NombreUsuario
        FROM dbo.TokenRecuperacion tr WITH (UPDLOCK, HOLDLOCK)
        JOIN dbo.Usuario u ON u.UsuarioId = tr.UsuarioId AND u.Activo = 1
        WHERE tr.TokenHash = @TokenHash AND tr.UsadoUtc IS NULL AND tr.RevocadoUtc IS NULL
          AND tr.ExpiraUtc > SYSUTCDATETIME();
        IF @TokenId IS NULL THROW 51012, N'Token invalido, usado o vencido.', 1;

        EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId;
        EXEC sys.sp_set_session_context @key = N'UsuarioAplicacion', @value = @NombreUsuario;
        EXEC sys.sp_set_session_context @key = N'DireccionIP', @value = @DireccionIP;
        EXEC sys.sp_set_session_context @key = N'CorrelationId', @value = @CorrelationId;

        DECLARE @NuevoSalt varbinary(32) = CRYPT_GEN_RANDOM(32);
        UPDATE dbo.Usuario
        SET PasswordSalt = @NuevoSalt,
            PasswordHash = HASHBYTES('SHA2_512', @NuevoSalt + CONVERT(varbinary(256), @ContrasenaNueva)),
            DebeCambiarPassword = 0,
            VersionSeguridad = VersionSeguridad + 1,
            UltimoCambioPasswordUtc = SYSUTCDATETIME(),
            ActualizadoUtc = SYSUTCDATETIME()
        WHERE UsuarioId = @UsuarioId;
        UPDATE dbo.TokenRecuperacion SET UsadoUtc = SYSUTCDATETIME() WHERE TokenRecuperacionId = @TokenId;
        UPDATE dbo.TokenRecuperacion SET RevocadoUtc = COALESCE(RevocadoUtc, SYSUTCDATETIME())
        WHERE UsuarioId = @UsuarioId AND TokenRecuperacionId <> @TokenId AND UsadoUtc IS NULL AND RevocadoUtc IS NULL;
        UPDATE dbo.Sesion SET RevocadaUtc = COALESCE(RevocadaUtc, SYSUTCDATETIME()) WHERE UsuarioId = @UsuarioId;
        COMMIT TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ListarPermisos
    @SesionHash varbinary(64), @DireccionIP varchar(45) = NULL, @CorrelationId uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int, @NombreUsuario varchar(50), @NombreVisible nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, 'ROLES_GESTIONAR', 0, 1,
            @UsuarioId OUTPUT, @NombreUsuario OUTPUT, @NombreVisible OUTPUT;
        SELECT PermisoId AS id, Codigo AS code, Nombre AS name, Modulo AS module
        FROM dbo.Permiso WHERE Activo = 1 ORDER BY Modulo, Codigo;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria; THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ListarUsuarios
    @SesionHash varbinary(64), @DireccionIP varchar(45) = NULL, @CorrelationId uniqueidentifier = NULL,
    @Pagina int = 1, @TamanoPagina tinyint = 25, @Busqueda nvarchar(160) = NULL,
    @Orden varchar(40) = 'name', @Direccion varchar(4) = 'asc'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina < 1 OR @TamanoPagina NOT IN (10,25,50) OR @Direccion NOT IN ('asc','desc')
        THROW 51006, N'Paginacion no valida.', 1;
    DECLARE @ActorId int, @Actor varchar(50), @ActorNombre nvarchar(120), @Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash, @DireccionIP, @CorrelationId, 'USUARIOS_GESTIONAR', 0, 1,
            @ActorId OUTPUT, @Actor OUTPUT, @ActorNombre OUTPUT;
        SELECT @Total = COUNT_BIG(*) FROM dbo.Usuario u
        WHERE NULLIF(@Busqueda,N'') IS NULL OR u.NombreUsuario LIKE N'%' + @Busqueda + N'%'
          OR u.NombreVisible LIKE N'%' + @Busqueda + N'%' OR u.CorreoRecuperacion LIKE N'%' + @Busqueda + N'%';

        SELECT u.UsuarioId AS id, u.NombreUsuario AS username, u.NombreVisible AS displayName,
               u.CorreoRecuperacion AS email, u.Activo AS active, u.DebeCambiarPassword AS mustChangePassword,
               u.ActualizadoUtc AS updatedAt, sys.fn_varbintohexstr(u.VersionFila) AS version,
               COALESCE((SELECT r.RolId AS id, r.Nombre AS name FROM dbo.Usuario_Rol ur
                         JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE ur.UsuarioId=u.UsuarioId
                         ORDER BY r.Nombre FOR JSON PATH), N'[]') AS roles
        FROM dbo.Usuario u
        WHERE NULLIF(@Busqueda,N'') IS NULL OR u.NombreUsuario LIKE N'%' + @Busqueda + N'%'
          OR u.NombreVisible LIKE N'%' + @Busqueda + N'%' OR u.CorreoRecuperacion LIKE N'%' + @Busqueda + N'%'
        ORDER BY
            CASE WHEN @Orden='name' AND @Direccion='asc' THEN u.NombreVisible END ASC,
            CASE WHEN @Orden='name' AND @Direccion='desc' THEN u.NombreVisible END DESC,
            CASE WHEN @Orden='username' AND @Direccion='asc' THEN u.NombreUsuario END ASC,
            CASE WHEN @Orden='username' AND @Direccion='desc' THEN u.NombreUsuario END DESC,
            CASE WHEN @Orden='status' AND @Direccion='asc' THEN u.Activo END ASC,
            CASE WHEN @Orden='status' AND @Direccion='desc' THEN u.Activo END DESC,
            CASE WHEN @Orden='updatedAt' AND @Direccion='asc' THEN u.ActualizadoUtc END ASC,
            CASE WHEN @Orden='updatedAt' AND @Direccion='desc' THEN u.ActualizadoUtc END DESC,
            u.UsuarioId ASC
        OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page, @TamanoPagina AS pageSize, @Total AS total,
               CONVERT(int, CEILING(@Total * 1.0 / @TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        EXEC dbo.sp_LimpiarContextoAuditoria; THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CrearUsuario
    @SesionHash varbinary(64), @DireccionIP varchar(45) = NULL, @CorrelationId uniqueidentifier = NULL,
    @NombreUsuario varchar(50), @NombreVisible nvarchar(120), @Correo nvarchar(254) = NULL,
    @PasswordTemporal nvarchar(128), @Roles dbo.TVP_ListaEnteros READONLY
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF LEN(@NombreUsuario) NOT BETWEEN 3 AND 50 OR @NombreUsuario LIKE '%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
        THROW 51006, N'Nombre de usuario no valido.', 1;
    IF LEN(@NombreVisible) NOT BETWEEN 2 AND 120 OR dbo.fn_ContrasenaCumplePolitica(@PasswordTemporal)=0
        THROW 51006, N'Datos de usuario no validos.', 1;
    DECLARE @ActorId int, @Actor varchar(50), @ActorNombre nvarchar(120), @NuevoId int;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'USUARIOS_GESTIONAR',0,1,
            @ActorId OUTPUT,@Actor OUTPUT,@ActorNombre OUTPUT;
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE NombreUsuario=@NombreUsuario) THROW 51004,N'Usuario duplicado.',1;
        IF EXISTS (SELECT 1 FROM @Roles x LEFT JOIN dbo.Rol r ON r.RolId=x.Id AND r.Activo=1 WHERE r.RolId IS NULL)
            THROW 51006,N'Rol no valido.',1;
        DECLARE @Salt varbinary(32)=CRYPT_GEN_RANDOM(32);
        INSERT dbo.Usuario(NombreUsuario,NombreVisible,CorreoRecuperacion,PasswordHash,PasswordSalt,DebeCambiarPassword)
        VALUES(@NombreUsuario,@NombreVisible,@Correo,HASHBYTES('SHA2_512',@Salt+CONVERT(varbinary(256),@PasswordTemporal)),@Salt,1);
        SET @NuevoId=CONVERT(int,SCOPE_IDENTITY());
        INSERT dbo.Usuario_Rol(UsuarioId,RolId,AsignadoPorUsuarioId) SELECT @NuevoId,Id,@ActorId FROM @Roles;
        INSERT dbo.PreferenciaUsuario(UsuarioId,Tema) VALUES(@NuevoId,'sistema');
        COMMIT TRANSACTION;
        SELECT u.UsuarioId AS id,u.NombreUsuario AS username,u.NombreVisible AS displayName,u.CorreoRecuperacion AS email,
               u.Activo AS active,u.DebeCambiarPassword AS mustChangePassword,sys.fn_varbintohexstr(u.VersionFila) AS version
        FROM dbo.Usuario u WHERE u.UsuarioId=@NuevoId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
        IF ERROR_NUMBER() IN (2601,2627) THROW 51004,N'Usuario duplicado.',1;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ActualizarUsuario
    @SesionHash varbinary(64), @DireccionIP varchar(45)=NULL, @CorrelationId uniqueidentifier=NULL,
    @UsuarioId int, @NombreVisible nvarchar(120)=NULL, @Correo nvarchar(254)=NULL, @CambiarCorreo bit=0,
    @Activo bit=NULL, @CambiarRoles bit=0, @Roles dbo.TVP_ListaEnteros READONLY, @Version binary(8)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @NombreVisible IS NOT NULL AND LEN(@NombreVisible) NOT BETWEEN 2 AND 120 THROW 51006,N'Nombre no valido.',1;
    DECLARE @ActorId int,@Actor varchar(50),@ActorNombre nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'USUARIOS_GESTIONAR',0,1,
            @ActorId OUTPUT,@Actor OUTPUT,@ActorNombre OUTPUT;
        BEGIN TRANSACTION;
        DECLARE @BloqueoAdministrador int;
        EXEC @BloqueoAdministrador=sys.sp_getapplock
            @Resource=N'SecureFinanceERP:Administradores',@LockMode='Exclusive',
            @LockOwner='Transaction',@LockTimeout=15000;
        IF @BloqueoAdministrador<0
            THROW 51004,N'No fue posible serializar el control de administradores.',1;
        DECLARE @ActivoActual bit;
        SELECT @ActivoActual=Activo FROM dbo.Usuario WITH(UPDLOCK,HOLDLOCK) WHERE UsuarioId=@UsuarioId;
        IF @ActivoActual IS NULL THROW 51003,N'Usuario inexistente.',1;
        IF EXISTS(SELECT 1 FROM @Roles x LEFT JOIN dbo.Rol r ON r.RolId=x.Id AND r.Activo=1 WHERE r.RolId IS NULL)
            THROW 51006,N'Rol no valido.',1;
        DECLARE @CambioActivo bit=CASE WHEN @Activo IS NOT NULL AND @Activo<>@ActivoActual THEN 1 ELSE 0 END,
                @CambioRolesEfectivo bit=0;
        IF @CambiarRoles=1 AND
        (
            EXISTS(SELECT 1 FROM dbo.Usuario_Rol ur WHERE ur.UsuarioId=@UsuarioId AND NOT EXISTS(SELECT 1 FROM @Roles x WHERE x.Id=ur.RolId))
            OR EXISTS(SELECT 1 FROM @Roles x WHERE NOT EXISTS(SELECT 1 FROM dbo.Usuario_Rol ur WHERE ur.UsuarioId=@UsuarioId AND ur.RolId=x.Id))
        ) SET @CambioRolesEfectivo=1;
        IF @CambioActivo=1 AND @Activo=0 AND EXISTS
        (
            SELECT 1 FROM dbo.Usuario_Rol ur JOIN dbo.Rol r ON r.RolId=ur.RolId AND r.Activo=1 AND r.EsAdministrador=1
            WHERE ur.UsuarioId=@UsuarioId
        ) AND NOT EXISTS
        (
            SELECT 1 FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId
            JOIN dbo.Rol r ON r.RolId=ur.RolId AND r.Activo=1 AND r.EsAdministrador=1
            WHERE u.Activo=1 AND u.UsuarioId<>@UsuarioId
        ) THROW 51004,N'No se puede desactivar al ultimo administrador.',1;

        UPDATE dbo.Usuario SET NombreVisible=COALESCE(@NombreVisible,NombreVisible),
            CorreoRecuperacion=CASE WHEN @CambiarCorreo=1 THEN @Correo ELSE CorreoRecuperacion END,
            Activo=COALESCE(@Activo,Activo), ActualizadoUtc=SYSUTCDATETIME(),
            VersionSeguridad=CASE WHEN @CambioActivo=1 OR @CambioRolesEfectivo=1 THEN VersionSeguridad+1 ELSE VersionSeguridad END
        WHERE UsuarioId=@UsuarioId AND VersionFila=@Version;
        IF @@ROWCOUNT=0 THROW 51009,N'Version obsoleta.',1;
        IF @CambioRolesEfectivo=1
        BEGIN
            IF EXISTS
            (
                SELECT 1 FROM dbo.Usuario_Rol ur JOIN dbo.Rol r ON r.RolId=ur.RolId AND r.EsAdministrador=1 AND r.Activo=1
                WHERE ur.UsuarioId=@UsuarioId
            ) AND NOT EXISTS(SELECT 1 FROM @Roles x JOIN dbo.Rol r ON r.RolId=x.Id AND r.EsAdministrador=1 AND r.Activo=1)
            AND NOT EXISTS
            (
                SELECT 1 FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId
                JOIN dbo.Rol r ON r.RolId=ur.RolId AND r.EsAdministrador=1 AND r.Activo=1
                WHERE u.Activo=1 AND u.UsuarioId<>@UsuarioId
            ) THROW 51004,N'No se puede retirar al ultimo administrador.',1;
            DELETE dbo.Usuario_Rol WHERE UsuarioId=@UsuarioId AND RolId NOT IN(SELECT Id FROM @Roles);
            INSERT dbo.Usuario_Rol(UsuarioId,RolId,AsignadoPorUsuarioId)
            SELECT @UsuarioId,x.Id,@ActorId FROM @Roles x
            WHERE NOT EXISTS(SELECT 1 FROM dbo.Usuario_Rol ur WHERE ur.UsuarioId=@UsuarioId AND ur.RolId=x.Id);
        END;
        IF @CambioActivo=1 OR @CambioRolesEfectivo=1
            UPDATE dbo.Sesion SET RevocadaUtc=COALESCE(RevocadaUtc,SYSUTCDATETIME()) WHERE UsuarioId=@UsuarioId;
        COMMIT TRANSACTION;
        SELECT u.UsuarioId AS id,u.NombreUsuario AS username,u.NombreVisible AS displayName,u.CorreoRecuperacion AS email,
               u.Activo AS active,u.DebeCambiarPassword AS mustChangePassword,sys.fn_varbintohexstr(u.VersionFila) AS version
        FROM dbo.Usuario u WHERE u.UsuarioId=@UsuarioId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria; THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GenerarPasswordTemporal
    @SesionHash varbinary(64), @DireccionIP varchar(45)=NULL, @CorrelationId uniqueidentifier=NULL,
    @UsuarioId int, @PasswordTemporal nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF dbo.fn_ContrasenaCumplePolitica(@PasswordTemporal)=0 THROW 51006,N'Password temporal no valido.',1;
    DECLARE @ActorId int,@Actor varchar(50),@ActorNombre nvarchar(120);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'USUARIOS_GESTIONAR',0,1,
            @ActorId OUTPUT,@Actor OUTPUT,@ActorNombre OUTPUT;
        IF @ActorId=@UsuarioId
            THROW 51004,N'Use Seguridad en su perfil para cambiar su propia password.',1;
        BEGIN TRANSACTION;
        IF NOT EXISTS(SELECT 1 FROM dbo.Usuario WITH(UPDLOCK,HOLDLOCK) WHERE UsuarioId=@UsuarioId) THROW 51003,N'Usuario inexistente.',1;
        DECLARE @Salt varbinary(32)=CRYPT_GEN_RANDOM(32);
        UPDATE dbo.Usuario SET PasswordSalt=@Salt,
            PasswordHash=HASHBYTES('SHA2_512',@Salt+CONVERT(varbinary(256),@PasswordTemporal)),
            DebeCambiarPassword=1,VersionSeguridad=VersionSeguridad+1,
            UltimoCambioPasswordUtc=SYSUTCDATETIME(),ActualizadoUtc=SYSUTCDATETIME()
        WHERE UsuarioId=@UsuarioId;
        UPDATE dbo.Sesion SET RevocadaUtc=COALESCE(RevocadaUtc,SYSUTCDATETIME()) WHERE UsuarioId=@UsuarioId;
        UPDATE dbo.TokenRecuperacion SET RevocadoUtc=COALESCE(RevocadoUtc,SYSUTCDATETIME())
        WHERE UsuarioId=@UsuarioId AND UsadoUtc IS NULL AND RevocadoUtc IS NULL;
        COMMIT TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria; THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ListarRoles
    @SesionHash varbinary(64), @DireccionIP varchar(45)=NULL, @CorrelationId uniqueidentifier=NULL,
    @Pagina int=1,@TamanoPagina tinyint=25,@Busqueda nvarchar(160)=NULL,@Orden varchar(40)='name',@Direccion varchar(4)='asc'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Pagina<1 OR @TamanoPagina NOT IN(10,25,50) OR @Direccion NOT IN('asc','desc') THROW 51006,N'Paginacion no valida.',1;
    DECLARE @ActorId int,@Actor varchar(50),@ActorNombre nvarchar(120),@Total bigint;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'ROLES_GESTIONAR',0,1,
            @ActorId OUTPUT,@Actor OUTPUT,@ActorNombre OUTPUT;
        SELECT @Total=COUNT_BIG(*) FROM dbo.Rol r WHERE NULLIF(@Busqueda,N'') IS NULL OR r.Nombre LIKE N'%'+@Busqueda+N'%' OR r.Descripcion LIKE N'%'+@Busqueda+N'%';
        SELECT r.RolId AS id,r.Nombre AS name,r.Descripcion AS description,r.Activo AS active,r.EsAdministrador AS administrator,
               r.ActualizadoUtc AS updatedAt,sys.fn_varbintohexstr(r.VersionFila) AS version,
               COALESCE((SELECT p.Codigo AS code,p.Nombre AS name,p.Modulo AS module FROM dbo.Rol_Permiso rp
                         JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId WHERE rp.RolId=r.RolId ORDER BY p.Codigo FOR JSON PATH),N'[]') AS permissions
        FROM dbo.Rol r WHERE NULLIF(@Busqueda,N'') IS NULL OR r.Nombre LIKE N'%'+@Busqueda+N'%' OR r.Descripcion LIKE N'%'+@Busqueda+N'%'
        ORDER BY CASE WHEN @Direccion='asc' THEN r.Nombre END ASC,CASE WHEN @Direccion='desc' THEN r.Nombre END DESC,r.RolId
        OFFSET (@Pagina-1)*@TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
        SELECT @Pagina AS page,@TamanoPagina AS pageSize,@Total AS total,CONVERT(int,CEILING(@Total*1.0/@TamanoPagina)) AS totalPages;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH EXEC dbo.sp_LimpiarContextoAuditoria; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CrearRol
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @Nombre nvarchar(60),@Descripcion nvarchar(200)=NULL,@Permisos dbo.TVP_CodigosPermiso READONLY
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF LEN(@Nombre) NOT BETWEEN 3 AND 60 THROW 51006,N'Nombre de rol no valido.',1;
    DECLARE @ActorId int,@Actor varchar(50),@ActorNombre nvarchar(120),@RolId int;
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'ROLES_GESTIONAR',0,1,@ActorId OUTPUT,@Actor OUTPUT,@ActorNombre OUTPUT;
        BEGIN TRANSACTION;
        IF EXISTS(SELECT 1 FROM dbo.Rol WHERE Nombre=CONVERT(varchar(60),@Nombre)) THROW 51004,N'Rol duplicado.',1;
        IF EXISTS(SELECT 1 FROM @Permisos x LEFT JOIN dbo.Permiso p ON p.Codigo=x.Codigo COLLATE Latin1_General_100_CI_AI AND p.Activo=1 WHERE p.PermisoId IS NULL)
            THROW 51006,N'Permiso no valido.',1;
        INSERT dbo.Rol(Nombre,Descripcion) VALUES(CONVERT(varchar(60),@Nombre),@Descripcion); SET @RolId=CONVERT(int,SCOPE_IDENTITY());
        INSERT dbo.Rol_Permiso(RolId,PermisoId,AsignadoPorUsuarioId)
        SELECT @RolId,p.PermisoId,@ActorId FROM @Permisos x JOIN dbo.Permiso p ON p.Codigo=x.Codigo COLLATE Latin1_General_100_CI_AI;
        COMMIT TRANSACTION;
        SELECT r.RolId AS id,r.Nombre AS name,r.Descripcion AS description,r.Activo AS active,sys.fn_varbintohexstr(r.VersionFila) AS version
        FROM dbo.Rol r WHERE r.RolId=@RolId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
        IF ERROR_NUMBER() IN(2601,2627) THROW 51004,N'Rol duplicado.',1;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ActualizarRol
    @SesionHash varbinary(64),@DireccionIP varchar(45)=NULL,@CorrelationId uniqueidentifier=NULL,
    @RolId int,@Nombre nvarchar(60)=NULL,@Descripcion nvarchar(200)=NULL,@CambiarDescripcion bit=0,
    @Activo bit=NULL,@CambiarPermisos bit=0,@Permisos dbo.TVP_CodigosPermiso READONLY,@Version binary(8)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    IF @Nombre IS NOT NULL AND LEN(@Nombre) NOT BETWEEN 3 AND 60 THROW 51006,N'Nombre de rol no valido.',1;
    DECLARE @ActorId int,@Actor varchar(50),@ActorNombre nvarchar(120),@EsAdmin bit,@NombreActual varchar(60);
    BEGIN TRY
        EXEC dbo.sp_ResolverSesion @SesionHash,@DireccionIP,@CorrelationId,'ROLES_GESTIONAR',0,1,@ActorId OUTPUT,@Actor OUTPUT,@ActorNombre OUTPUT;
        BEGIN TRANSACTION;
        SELECT @EsAdmin=EsAdministrador,@NombreActual=Nombre FROM dbo.Rol WITH(UPDLOCK,HOLDLOCK) WHERE RolId=@RolId;
        IF @EsAdmin IS NULL THROW 51003,N'Rol inexistente.',1;
        IF @EsAdmin=1 AND @Activo=0 THROW 51004,N'No se puede desactivar el rol administrador protegido.',1;
        IF @EsAdmin=1 AND @Nombre IS NOT NULL AND CONVERT(varchar(60),@Nombre)<>@NombreActual
            THROW 51004,N'No se puede renombrar el rol administrador protegido.',1;
        IF EXISTS(SELECT 1 FROM @Permisos x LEFT JOIN dbo.Permiso p ON p.Codigo=x.Codigo COLLATE Latin1_General_100_CI_AI AND p.Activo=1 WHERE p.PermisoId IS NULL)
            THROW 51006,N'Permiso no valido.',1;
        IF @EsAdmin=1 AND @CambiarPermisos=1 AND
           (NOT EXISTS(SELECT 1 FROM @Permisos WHERE Codigo='USUARIOS_GESTIONAR') OR NOT EXISTS(SELECT 1 FROM @Permisos WHERE Codigo='ROLES_GESTIONAR'))
            THROW 51004,N'El rol administrador debe conservar permisos de seguridad.',1;
        UPDATE dbo.Rol SET Nombre=COALESCE(CONVERT(varchar(60),@Nombre),Nombre),
            Descripcion=CASE WHEN @CambiarDescripcion=1 THEN @Descripcion ELSE Descripcion END,
            Activo=COALESCE(@Activo,Activo),ActualizadoUtc=SYSUTCDATETIME()
        WHERE RolId=@RolId AND VersionFila=@Version;
        IF @@ROWCOUNT=0 THROW 51009,N'Version obsoleta.',1;
        IF @CambiarPermisos=1
        BEGIN
            DELETE dbo.Rol_Permiso WHERE RolId=@RolId AND PermisoId NOT IN(SELECT p.PermisoId FROM @Permisos x JOIN dbo.Permiso p ON p.Codigo=x.Codigo COLLATE Latin1_General_100_CI_AI);
            INSERT dbo.Rol_Permiso(RolId,PermisoId,AsignadoPorUsuarioId)
            SELECT @RolId,p.PermisoId,@ActorId FROM @Permisos x JOIN dbo.Permiso p ON p.Codigo=x.Codigo COLLATE Latin1_General_100_CI_AI
            WHERE NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@RolId AND rp.PermisoId=p.PermisoId);
            UPDATE u SET VersionSeguridad=VersionSeguridad+1,ActualizadoUtc=SYSUTCDATETIME()
            FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId WHERE ur.RolId=@RolId;
            UPDATE s SET RevocadaUtc=COALESCE(s.RevocadaUtc,SYSUTCDATETIME())
            FROM dbo.Sesion s JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=s.UsuarioId WHERE ur.RolId=@RolId;
        END;
        COMMIT TRANSACTION;
        SELECT r.RolId AS id,r.Nombre AS name,r.Descripcion AS description,r.Activo AS active,sys.fn_varbintohexstr(r.VersionFila) AS version
        FROM dbo.Rol r WHERE r.RolId=@RolId;
        EXEC dbo.sp_LimpiarContextoAuditoria;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        EXEC dbo.sp_LimpiarContextoAuditoria;
        IF ERROR_NUMBER() IN(2601,2627) THROW 51004,N'Rol duplicado.',1;
        THROW;
    END CATCH;
END;
GO
/* ===== FIN: database\03_security.sql ===== */

/* ===== INICIO: database\04_catalogs.sql ===== */
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
/* ===== FIN: database\04_catalogs.sql ===== */

/* ===== INICIO: database\05_sales_reports.sql ===== */
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
/* ===== FIN: database\05_sales_reports.sql ===== */

/* ===== INICIO: database\06_audit.sql ===== */
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
/* ===== FIN: database\06_audit.sql ===== */

/* ===== INICIO: database\07_permissions.sql ===== */
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
/* ===== FIN: database\07_permissions.sql ===== */

/* ===== INICIO: database\migrations\0002_security_contract_hardening.sql ===== */
:on error exit
USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.SchemaMigration',N'U') IS NULL
    THROW 51006,N'No existe el registro de migraciones.',1;

EXEC dbo.sp_LimpiarContextoAuditoria;
IF EXISTS(SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId='0002_security_contract_hardening')
BEGIN
    PRINT N'La migracion 0002_security_contract_hardening ya estaba aplicada.';
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'MotivoAuditoria',@value=N'Migracion 0002: endurecimiento de contrato y seguridad';

    DELETE rp
    FROM dbo.Rol_Permiso AS rp
    JOIN dbo.Rol AS r ON r.RolId=rp.RolId AND r.EsAdministrador=1
    JOIN dbo.Permiso AS p ON p.PermisoId=rp.PermisoId
    WHERE p.Codigo='VENTAS_CREAR';

    UPDATE dbo.Bitacora_DDL
    SET Comando=NULL
    WHERE Comando IS NOT NULL;

    INSERT dbo.SchemaMigration(MigrationId,Descripcion)
    VALUES('0002_security_contract_hardening',N'Contexto de pool, administrador minimo, DDL seguro y contratos SQL');
    COMMIT TRANSACTION;
    EXEC dbo.sp_LimpiarContextoAuditoria;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    EXEC dbo.sp_LimpiarContextoAuditoria;
    THROW;
END CATCH;
GO
/* ===== FIN: database\migrations\0002_security_contract_hardening.sql ===== */

/* ===== INICIO: database\provision-bootstrap-admin.sql ===== */
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

DECLARE @NombreUsuarioInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(BootstrapUsername))',
        @NombreVisibleInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(BootstrapDisplayName))',
        @PasswordInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(BootstrapPassword))';

IF LEN(@NombreUsuarioInput) NOT BETWEEN 3 AND 50
   OR @NombreUsuarioInput LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
    THROW 51006,N'BootstrapUsername no es valido.',1;
IF LEN(@NombreVisibleInput) NOT BETWEEN 2 AND 120
    THROW 51006,N'BootstrapDisplayName no es valido.',1;
IF LEN(@PasswordInput) NOT BETWEEN 12 AND 128
    THROW 51006,N'BootstrapPassword no es valido.',1;

DECLARE @NombreUsuario varchar(50)=CONVERT(varchar(50),@NombreUsuarioInput),
        @NombreVisible nvarchar(120)=CONVERT(nvarchar(120),@NombreVisibleInput),
        @Password nvarchar(128)=CONVERT(nvarchar(128),@PasswordInput),
        @RolId int,@UsuarioId int;

BEGIN TRY
    BEGIN TRANSACTION;
    SELECT @RolId=RolId FROM dbo.Rol WITH(UPDLOCK,HOLDLOCK) WHERE EsAdministrador=1;
    IF @RolId IS NULL
    BEGIN
        INSERT dbo.Rol(Nombre,Descripcion,EsAdministrador,Activo)
        VALUES('Administrador',N'Administracion integral y seguridad del sistema',1,1);
        SET @RolId=CONVERT(int,SCOPE_IDENTITY());
    END
    ELSE
        UPDATE dbo.Rol SET EsAdministrador=1,Activo=1,ActualizadoUtc=SYSUTCDATETIME() WHERE RolId=@RolId;

    INSERT dbo.Rol_Permiso(RolId,PermisoId)
    SELECT @RolId,p.PermisoId FROM dbo.Permiso p WHERE p.Activo=1
      AND p.Codigo<>'VENTAS_CREAR'
      AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@RolId AND rp.PermisoId=p.PermisoId);

    SELECT @UsuarioId=UsuarioId FROM dbo.Usuario WITH(UPDLOCK,HOLDLOCK) WHERE NombreUsuario=@NombreUsuario;
    IF @UsuarioId IS NULL
    BEGIN
        IF dbo.fn_ContrasenaCumplePolitica(@Password)=0
            THROW 51006,N'BootstrapPassword no cumple la politica.',1;
        DECLARE @Salt varbinary(32)=CRYPT_GEN_RANDOM(32);
        INSERT dbo.Usuario
            (NombreUsuario,NombreVisible,CorreoRecuperacion,PasswordHash,PasswordSalt,DebeCambiarPassword,Activo)
        VALUES
            (@NombreUsuario,@NombreVisible,NULL,HASHBYTES('SHA2_512',@Salt+CONVERT(varbinary(256),@Password)),@Salt,1,1);
        SET @UsuarioId=CONVERT(int,SCOPE_IDENTITY());
        INSERT dbo.PreferenciaUsuario(UsuarioId,Tema) VALUES(@UsuarioId,'sistema');
    END;

    IF NOT EXISTS(SELECT 1 FROM dbo.Usuario_Rol WHERE UsuarioId=@UsuarioId AND RolId=@RolId)
        INSERT dbo.Usuario_Rol(UsuarioId,RolId,AsignadoPorUsuarioId) VALUES(@UsuarioId,@RolId,@UsuarioId);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT @UsuarioId AS bootstrapUserId,@NombreUsuario AS bootstrapUsername,
       CONVERT(bit,CASE WHEN EXISTS(SELECT 1 FROM dbo.Usuario WHERE UsuarioId=@UsuarioId AND DebeCambiarPassword=1) THEN 1 ELSE 0 END) AS mustChangePassword;
GO
/* ===== FIN: database\provision-bootstrap-admin.sql ===== */

/* ===== INICIO: database\seed-demo.sql ===== */
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
/* ===== FIN: database\seed-demo.sql ===== */
USE [$(DatabaseName)];
GO

IF NOT EXISTS (SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId = '0001_baseline')
    THROW 51006, N'La migracion base no quedo registrada.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.SchemaMigration WHERE MigrationId = '0002_security_contract_hardening')
    THROW 51006, N'La migracion de seguridad no quedo registrada.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE EsAdministrador = 1 AND Activo = 1)
    THROW 51006, N'No se creo o encontro el rol administrador activo.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE NombreUsuario = '$(ESCAPE_SQUOTE(BootstrapUsername))' AND Activo = 1)
    THROW 51006, N'No se creo o encontro el usuario bootstrap activo.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE Codigo IN ('DEMO-001', 'DEMO-002'))
    THROW 51006, N'Los productos semilla no quedaron disponibles.', 1;
GO

PRINT N'Instalacion unificada de SecureFinance ERP completada correctamente.';
GO
