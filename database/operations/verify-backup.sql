:on error exit
USE [master];
GO
DECLARE @Archivo nvarchar(4000)=N'$(ESCAPE_SQUOTE(BackupFile))';
IF LEN(@Archivo) NOT BETWEEN 5 AND 4000 THROW 51006,N'BackupFile no es valido.',1;
DECLARE @Sql nvarchar(max)=N'RESTORE VERIFYONLY FROM DISK=N'''+REPLACE(@Archivo,N'''',N'''''')+N''' WITH CHECKSUM;';
EXEC sys.sp_executesql @Sql;
GO
