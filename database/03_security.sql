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
