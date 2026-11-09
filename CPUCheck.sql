/* 
This will get you the top 50 process that
are the most CPU Intensive.
*/

SELECT TOP 50
qs.total_worker_time/qs.execution_count AS [Avg CPU Time],
	SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
		((CASE qs.statement_end_offset
			WHEN -1 then DATALENGTH(qt.text)
			ELSE qs.statement_end_offset
			END - qs.statement_start_offset)/2) + 1) AS statement_text,
qt.dbid,
dbname=db_name(qt.dbid),
qt.objectid
FROM
	sys.dm_exec_query_stats qs
CROSS APPLY 
	sys.dm_exec_sql_text(qs.sql_handle) as qt
ORDER BY
	[Avg CPU Time] DESC