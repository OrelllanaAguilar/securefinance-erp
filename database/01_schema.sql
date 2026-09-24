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
