--dbcc memorystatus
--

--To call this from Azure Synapse Analytics, use the name sys.dm_pdw_nodes_os_memory_clerks. 
--This syntax is not supported by serverless SQL pool in Azure Synapse Analytics.

--select * from sys.dm_os_memory_clerks
--
--select 
--	type,
--	sum(pages_kb) 
--from 
--	sys.dm_os_memory_clerks
--where 
--	pages_kb != 0
--group by type

--select 
--	type,
--	sum(pages_kb) as pages_kb,
--  sum (virtual_memory_reserved_kb) AS virtual_memory_reserved_kb ,
--  sum(virtual_memory_committed_kb) AS virtual_memory_committed_kb
--from 
--	sys.dm_os_memory_clerks
--where 
--	pages_kb != 0
--group by type

--sp_configure 'show advanced options', 1
--RECONFIGURE
--GO

--sp_spaceused
--
--select
--	SUM(awe_allocated_kb) / 1024
--from
--	sys.dm_os_memory_clerks

xp_msver