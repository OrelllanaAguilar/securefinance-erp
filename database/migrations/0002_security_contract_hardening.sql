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
