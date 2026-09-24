:on error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF @@TRANCOUNT<>0
    THROW 51006,N'La demostracion requiere una conexion sin transaccion previa.',1;

CREATE TABLE #DemostracionSave
(
    Id int NOT NULL PRIMARY KEY,
    Descripcion nvarchar(80) NOT NULL
);

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT #DemostracionSave VALUES(1,N'Persistiria si se confirmara la transaccion exterior');
    SAVE TRANSACTION PuntoDidactico;

    BEGIN TRY
        INSERT #DemostracionSave VALUES(2,N'Esta unidad se revierte hasta el punto de guardado');
        THROW 52002,N'Fallo didactico dentro de la unidad secundaria.',1;
    END TRY
    BEGIN CATCH
        /* Un savepoint solo es recuperable si la transaccion sigue confirmable. */
        IF XACT_STATE()=1
            ROLLBACK TRANSACTION PuntoDidactico;
        ELSE
            THROW;
    END CATCH;

    IF XACT_STATE()<>1
        THROW 51006,N'La transaccion exterior no quedo confirmable.',1;
    IF EXISTS(SELECT 1 FROM #DemostracionSave WHERE Id=2)
       OR NOT EXISTS(SELECT 1 FROM #DemostracionSave WHERE Id=1)
        THROW 51006,N'La demostracion SAVE TRANSACTION no produjo el estado esperado.',1;

    /* Es una demostracion: tampoco se conserva la fila exterior. */
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    /* XACT_STATE=-1 exige rollback completo; 1 tambien se revierte para aislar la prueba. */
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    IF OBJECT_ID(N'tempdb..#DemostracionSave',N'U') IS NOT NULL DROP TABLE #DemostracionSave;
    THROW;
END CATCH;

IF EXISTS(SELECT 1 FROM #DemostracionSave)
    THROW 51006,N'La demostracion conservo cambios fuera de su alcance.',1;
IF @@TRANCOUNT<>0
    THROW 51006,N'La demostracion dejo una transaccion abierta.',1;
DROP TABLE #DemostracionSave;
SET XACT_ABORT ON;
SELECT 'ok' AS saveTransactionDemo;
GO
