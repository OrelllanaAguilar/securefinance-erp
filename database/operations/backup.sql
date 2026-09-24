:on error exit
USE [master];
GO
DECLARE @BaseInput nvarchar(4000)=N'$(ESCAPE_SQUOTE(DatabaseName))',
        @Archivo nvarchar(4000)=N'$(ESCAPE_SQUOTE(BackupFile))';
IF LEN(@BaseInput) NOT BETWEEN 1 AND 128
   OR @BaseInput LIKE N'%[^A-Za-z0-9_]%' COLLATE Latin1_General_100_BIN2
    THROW 51006,N'DatabaseName no es valido.',1;
DECLARE @Base sysname=CONVERT(sysname,@BaseInput);
IF DB_ID(@Base) IS NULL THROW 51003,N'La base indicada no existe.',1;
IF LEN(@Archivo) NOT BETWEEN 5 AND 4000 THROW 51006,N'BackupFile no es valido.',1;
DECLARE @Sql nvarchar(max)=N'BACKUP DATABASE '+QUOTENAME(@Base)+N' TO DISK=N'''+REPLACE(@Archivo,N'''',N'''''')+N''''+
    N' WITH COPY_ONLY, CHECKSUM, NOINIT, STATS=10;';
EXEC sys.sp_executesql @Sql;
GO
