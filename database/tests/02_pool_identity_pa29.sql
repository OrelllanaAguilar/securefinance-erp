:on error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;

EXEC sys.sp_set_session_context @key=N'UsuarioId',@value=2147483647;
EXEC sys.sp_set_session_context @key=N'UsuarioAplicacion',@value=N'contexto-residual-no-valido';
EXEC sys.sp_set_session_context @key=N'DireccionIP',@value=N'203.0.113.99';
EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=N'00000000-0000-0000-0000-000000000001';
EXEC sys.sp_set_session_context @key=N'MotivoAuditoria',@value=N'contexto-residual-no-valido';
BEGIN TRY
    DECLARE @Id int,@Usuario varchar(50),@Nombre nvarchar(120);
    EXEC dbo.sp_ResolverSesion
        @SesionHash=0x00,@DireccionIP='127.0.0.1',@CorrelationId=NULL,
        @UsuarioId=@Id OUTPUT,@NombreUsuario=@Usuario OUTPUT,@NombreVisible=@Nombre OUTPUT;
    THROW 51006,N'Una sesion invalida fue aceptada.',1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER()<>51001 THROW;
END CATCH;
IF SESSION_CONTEXT(N'UsuarioId') IS NOT NULL
   OR SESSION_CONTEXT(N'UsuarioAplicacion') IS NOT NULL
   OR SESSION_CONTEXT(N'DireccionIP') IS NOT NULL
   OR SESSION_CONTEXT(N'CorrelationId') IS NOT NULL
   OR SESSION_CONTEXT(N'MotivoAuditoria') IS NOT NULL
    THROW 51006,N'El contexto residual del pool no fue limpiado.',1;
SELECT 'ok' AS pa29ContextIsolation;
GO
