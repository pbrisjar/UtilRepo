/*
Create this trigger on a table to disallow all changes.
Modify trigger name and table name as desired.
Note that this version will only work if there are no cascading 
foreign keys on the table.
*/

CREATE TRIGGER tr_NoChanges/*trigger name*/ on dbo.t1/*table name*/
INSTEAD OF INSERT, UPDATE, DELETE
AS
 RAISERROR('Database is in maintenance.  No alterations to data are permitted at this time.',11,1)
GO

/* Version 2
Use this one if there are cascades on the table.
*/

CREATE TRIGGER tr_NoChanges2/*trigger name*/ on dbo.TestTable/*table name*/
FOR INSERT, UPDATE, DELETE
AS
 ROLLBACK TRANSACTION	
 RAISERROR('Database is in maintenance.  No alterations to data are permitted at this time.',11,1)
GO

/* Command to drop the triggers */

IF OBJECT_ID ('tr_NoChanges','TR') IS NOT NULL
  DROP TRIGGER tr_NoChanges
GO

IF OBJECT_ID ('tr_NoChanges2','TR') IS NOT NULL
  DROP TRIGGER tr_NoChanges2
GO
