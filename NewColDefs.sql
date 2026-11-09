--script to verify the column type / size of those that were candidates for change
--This should also catch all computed columns.

select 
	sc.name as [ColumnName],
	st.name as [ColumnType],
	sc.max_length,
	sc.is_computed
from sys.columns sc
INNER JOIN
	sys.types st
ON
	sc.system_type_id = st.system_type_id
where 
	sc.object_id = OBJECT_ID('dbo.t2')
and
	(
	sc.name in 
		('TestCol'
)
 or 
sc.is_computed = 1)
Order By ColumnName