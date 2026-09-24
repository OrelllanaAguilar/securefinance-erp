:on error exit
USE [master];
GO
DECLARE @DestinoInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(RestoreDatabaseName))',
        @Archivo nvarchar(4000)=N'$(ESCAPE_SQUOTE(BackupFile))',
        @LogicoDatosInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(LogicalDataName))',
        @LogicoLogInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(LogicalLogName))',
        @Datos nvarchar(4000)=N'$(ESCAPE_SQUOTE(RestoreDataFile))',
        @Log nvarchar(4000)=N'$(ESCAPE_SQUOTE(RestoreLogFile))';
IF LEN(@DestinoInput) NOT BETWEEN 13 AND 128
   OR @DestinoInput LIKE N'%[^A-Za-z0-9_]%' COLLATE Latin1_General_100_BIN2
    THROW 51006,N'RestoreDatabaseName no es valido.',1;
IF LEN(@LogicoDatosInput) NOT BETWEEN 1 AND 128 OR LEN(@LogicoLogInput) NOT BETWEEN 1 AND 128
    THROW 51006,N'Los nombres logicos no son validos.',1;
IF LEN(@Archivo) NOT BETWEEN 5 AND 4000 OR LEN(@Datos) NOT BETWEEN 5 AND 4000 OR LEN(@Log) NOT BETWEEN 5 AND 4000
    THROW 51006,N'Las rutas de restauracion no son validas.',1;
DECLARE @Destino sysname=CONVERT(sysname,@DestinoInput),
        @LogicoDatos sysname=CONVERT(sysname,@LogicoDatosInput),
        @LogicoLog sysname=CONVERT(sysname,@LogicoLogInput);
IF RIGHT(LOWER(@Destino),12)<>N'_restoretest'
    THROW 51006,N'La base de restauracion debe terminar en _RestoreTest.',1;
IF DB_ID(@Destino) IS NOT NULL
    THROW 51004,N'La base de restauracion ya existe; no se sobrescribira.',1;
DECLARE @Sql nvarchar(max)=N'RESTORE DATABASE '+QUOTENAME(@Destino)+N' FROM DISK=N'''+REPLACE(@Archivo,N'''',N'''''')+
    N''' WITH MOVE N'''+REPLACE(@LogicoDatos,N'''',N'''''')+N''' TO N'''+REPLACE(@Datos,N'''',N'''''')+
    N''', MOVE N'''+REPLACE(@LogicoLog,N'''',N'''''')+N''' TO N'''+REPLACE(@Log,N'''',N'''''')+
    N''', CHECKSUM, RECOVERY, STATS=10;';
EXEC sys.sp_executesql @Sql;

DECLARE @Invalidar nvarchar(max)=N'USE '+QUOTENAME(@Destino)+N';
SET XACT_ABORT ON;
BEGIN TRANSACTION;
UPDATE dbo.Sesion SET RevocadaUtc=COALESCE(RevocadaUtc,SYSUTCDATETIME()) WHERE RevocadaUtc IS NULL;
DECLARE @Sesiones bigint=@@ROWCOUNT;
UPDATE dbo.TokenRecuperacion SET RevocadoUtc=COALESCE(RevocadoUtc,SYSUTCDATETIME())
WHERE UsadoUtc IS NULL AND RevocadoUtc IS NULL;
DECLARE @Tokens bigint=@@ROWCOUNT;
COMMIT TRANSACTION;
SELECT @Sesiones AS sessionsRevoked,@Tokens AS recoveryTokensRevoked;';
EXEC sys.sp_executesql @Invalidar;

DECLARE @Comprobar nvarchar(max)=N'DBCC CHECKDB ('+QUOTENAME(@Destino,N'''')+N') WITH NO_INFOMSGS, ALL_ERRORMSGS;';
EXEC sys.sp_executesql @Comprobar;
GO
