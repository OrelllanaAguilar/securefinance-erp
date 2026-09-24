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
