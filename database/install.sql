:on error exit
PRINT N'Instalando SecureFinance ERP en $(ESCAPE_SQUOTE(DatabaseName))...';

:r .\database\00_database.sql
:r .\database\01_schema.sql
:r .\database\02_functions.sql
:r .\database\03_security.sql
:r .\database\04_catalogs.sql
:r .\database\05_sales_reports.sql
:r .\database\06_audit.sql
:r .\database\07_permissions.sql
:r .\database\migrations\0002_security_contract_hardening.sql

PRINT N'Instalacion de SecureFinance ERP completada.';
GO
