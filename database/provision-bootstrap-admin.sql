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
