:on error exit
USE [master];
GO

DECLARE @DatabaseNameInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(DatabaseName))',
        @LoginInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(ApiLoginName))',
        @PasswordInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(ApiLoginPassword))';
IF LEN(@DatabaseNameInput) NOT BETWEEN 1 AND 128
   OR @DatabaseNameInput LIKE N'%[^A-Za-z0-9_]%' COLLATE Latin1_General_100_BIN2
    THROW 51006,N'DatabaseName no es valido.',1;
IF DB_ID(@DatabaseNameInput) IS NULL
    THROW 51003,N'La base indicada no existe.',1;
IF LEN(@LoginInput) NOT BETWEEN 1 AND 128
   OR @LoginInput LIKE N'%[^A-Za-z0-9_.-]%' COLLATE Latin1_General_100_BIN2
    THROW 51006,N'ApiLoginName no es valido.',1;
IF LEN(@PasswordInput) NOT BETWEEN 16 AND 128 OR @PasswordInput LIKE N'%CHANGE_ME%'
    THROW 51006,N'ApiLoginPassword debe ser privado y tener al menos 16 caracteres.',1;
DECLARE @Login sysname=CONVERT(sysname,@LoginInput),@Password nvarchar(128)=CONVERT(nvarchar(128),@PasswordInput);
IF SUSER_ID(@Login) IS NULL
BEGIN
    DECLARE @CrearLogin nvarchar(max)=N'CREATE LOGIN '+QUOTENAME(@Login)+N' WITH PASSWORD='+QUOTENAME(@Password,N'''')+
        N', CHECK_POLICY=ON, CHECK_EXPIRATION=OFF, DEFAULT_DATABASE='+QUOTENAME(CONVERT(sysname,@DatabaseNameInput))+N';';
    EXEC sys.sp_executesql @CrearLogin;
END;
GO

USE [$(DatabaseName)];
GO
DECLARE @Login sysname=CONVERT(sysname,N'$(ESCAPE_SQUOTE(ApiLoginName))');
IF DATABASE_PRINCIPAL_ID(@Login) IS NULL
BEGIN
    DECLARE @CrearUsuario nvarchar(max)=N'CREATE USER '+QUOTENAME(@Login)+N' FOR LOGIN '+QUOTENAME(@Login)+N';';
    EXEC sys.sp_executesql @CrearUsuario;
END;
IF NOT EXISTS
(
    SELECT 1 FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id=rm.member_principal_id
    WHERE r.name=N'SecureFinanceApiExecutor' AND m.name=@Login
)
BEGIN
    DECLARE @AgregarRol nvarchar(max)=N'ALTER ROLE SecureFinanceApiExecutor ADD MEMBER '+QUOTENAME(@Login)+N';';
    EXEC sys.sp_executesql @AgregarRol;
END;
GO
