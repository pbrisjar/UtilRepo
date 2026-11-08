--Creates a script to modify columns from ntext to vachar(400)
--Skips those with a max datalength greater than 400


Create table #columns (cnt int Identity (1, 1), colname sysname, colsize int)
Declare 
	@cnt int, 
	@tick int,
	@size int,
	@colname sysname,
	@tble varchar(50)

set @tble = 'dbo.t2'

INSERT INTO #columns (colname)
select 
	sc.name
from sys.columns sc
INNER JOIN
	sys.types st
ON
	sc.system_type_id = st.system_type_id
where 
	sc.object_id = OBJECT_ID(@tble)
and
	st.name IN ('ntext', 'varchar') --catches those already changed
--and
--	sc.name in -- Remove this to get all, change to NOT IN to exclude listed columns
--		('')

select @cnt = count(*) from #columns

SET @tick = 1

WHILE @tick <= @cnt
BEGIN

	SELECT @colname = colname
	from #columns where cnt = @tick

	SELECT 
		@size = MAX(LEN(@colname)) 
	FROM dbo.t2 

	UPDATE #Columns set colsize = @size where cnt = @tick

	set @tick = @tick + 1

END

select 
'ALTER TABLE [' + @tble + '] ALTER COLUMN ['+ colname +'] VARCHAR (400)'
from #columns where colsize < 401


DROP TABLE #columns
