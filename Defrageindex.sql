/*
This is a script designed to run defragmentation / maintenance on DB's.
Note that this has been modified/tested for SQL Server 2025.
*/

USE TestDB --set this for the DB in which you want the frag utilities to reside
GO

----------------------------------------------------------
-- This creates a table to log all activity and results --
----------------------------------------------------------

-- Table is fragreport.  Rename as desired for naming conventions, etc.

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[fragreport]') AND type in (N'U'))
	drop table [dbo].[fragreport]
GO

CREATE TABLE [dbo].[fragreport] (
	[fid] [int] IDENTITY (1, 1) NOT NULL ,
	[TimeProc] [datetime] NULL ,
	[ObjectName] [sysname] NOT NULL ,
	[ObjectId] [int] NULL ,
	[IndexName] [sysname] NULL ,
	[IndexId] [int] NULL ,
	database_id [int] NULL ,
	partition_number [int] NULL ,	
	index_type_desc	[varchar] (100)  COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,
	alloc_unit_type_desc [varchar] (100)  COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,	
	index_depth [int] NULL ,	
	index_level	[int] NULL ,
	avg_fragmentation_in_percent [float] NULL ,	
	fragment_count [bigint] NULL ,	
	avg_fragment_size_in_pages [float] NULL ,	
	page_count [bigint] NULL ,	
	avg_page_space_used_in_percent [float] NULL ,	
	record_count [bigint] NULL ,	
	ghost_record_count [bigint] NULL ,	
	version_ghost_record_count [bigint] NULL ,	
	min_record_size_in_bytes [bigint] NULL ,	
	max_record_size_in_bytes [bigint] NULL ,	
	avg_record_size_in_bytes [float] NULL ,	
	forwarded_record_count [bigint] NULL ,	
	compressed_page_count [bigint] NULL ,	
	hobt_id [bigint] NULL ,
	columnstore_delete_buffer_state [bigint] NULL ,	
	columnstore_delete_buffer_state_desc [varchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,	
	version_record_count [bigint] NULL ,	
	inrow_version_record_count [bigint] NULL ,	
	inrow_diff_version_record_count [bigint] NULL ,	
	total_inrow_version_payload_size_in_bytes [bigint] NULL ,	
	offrow_regular_version_record_count [bigint] NULL ,	
	offrow_long_term_version_record_count [bigint] NULL ,
	[DBName] [varchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,
	[PrePost] [varchar] (20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL --PRE, POST and possible REINDEXED
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[fragreport] WITH NOCHECK ADD 
	CONSTRAINT [PK_fragreport] PRIMARY KEY  CLUSTERED 
	(
		[fid]
	)  ON [PRIMARY] 
GO


-------------------------------------------------------
-- Run this from installed DB and supply any database name --
-------------------------------------------------------

--Stored proc is named sp_IndexDefragAndRebuild.  Rename as desired for naming conventions

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[sp_IndexDefragAndRebuild]') AND type in (N'P'))
drop procedure [dbo].[sp_IndexDefragAndRebuild]
GO

SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO


CREATE PROCEDURE sp_IndexDefragAndRebuild
	@dbname varchar(100),
	@catswitch int = 1, --0 for do nothing, 1 for reorganize, 2 for rebuild.  All other values ignored.
	@FragPages int = 0, 
	@FragPercent int = 5 
AS

SET NOCOUNT ON

-- create the temp tables

CREATE TABLE #tables(
	rid int identity (1,1),
	tabid int,
	[name] varchar(100),
	schemaname varchar(100)
)

CREATE TABLE #catalogs
	(cid int identity (1,1),
	 catname sysname)

CREATE TABLE #fragreport(
	[fid] [int] IDENTITY (1, 1) NOT NULL ,
	[TimeProc] [datetime]  default getdate() ,
	[ObjectName] [sysname] NOT NULL ,
	[ObjectId] [int] NULL ,
	[IndexName] [sysname] NULL ,
	[IndexId] [int] NULL ,
	database_id [int] NULL ,
	partition_number [int] NULL ,	
	index_type_desc	[varchar] (100)  COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,
	alloc_unit_type_desc [varchar] (100)  COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,	
	index_depth [int] NULL ,	
	index_level	[int] NULL ,
	avg_fragmentation_in_percent [float] NULL ,	
	fragment_count [bigint] NULL ,	
	avg_fragment_size_in_pages [float] NULL ,	
	page_count [bigint] NULL ,	
	avg_page_space_used_in_percent [float] NULL ,	
	record_count [bigint] NULL ,	
	ghost_record_count [bigint] NULL ,	
	version_ghost_record_count [bigint] NULL ,	
	min_record_size_in_bytes [bigint] NULL ,	
	max_record_size_in_bytes [bigint] NULL ,	
	avg_record_size_in_bytes [float] NULL ,	
	forwarded_record_count [bigint] NULL ,	
	compressed_page_count [bigint] NULL ,	
	hobt_id [bigint] NULL ,
	columnstore_delete_buffer_state [bigint] NULL ,	
	columnstore_delete_buffer_state_desc [varchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,	
	version_record_count [bigint] NULL ,	
	inrow_version_record_count [bigint] NULL ,	
	inrow_diff_version_record_count [bigint] NULL ,	
	total_inrow_version_payload_size_in_bytes [bigint] NULL ,	
	offrow_regular_version_record_count [bigint] NULL ,	
	offrow_long_term_version_record_count [bigint] NULL ,
	[DBName] [varchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL ,
	[PrePost] [varchar] (20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL
)

CREATE TABLE #reindex(
	rid int identity (1,1),
	ObjectName sysname,
	IndexName sysname,
	schemaname varchar(100),
	ObjectID int,
	IndexID int
)

DECLARE @numtables int,
	@numreindexes int,
	@tabcount int,
	@recount int,
	@currtable int,
	@tabname varchar(100),
	@schemaname varchar(100),
	@indname varchar(100),
	@catcount int,
	@numcats int,
	@currcat int,
	@catname varchar(100)
--these are all for flow control through the various loops.

SET @dbname = LTRIM(RTRIM(@dbname))

SET @tabcount = 1

--Get all user tables
EXEC(
'INSERT INTO #tables([tabid], [name], schemaname)
SELECT 
	so.[object_id], 
	ltrim(rtrim(so.[name])) ,
	sc.[name] 
FROM '+ 
	@dbname + '.sys.objects so 
	inner join '+ 
	@dbname + '.sys.schemas sc
on so.schema_id = sc.schema_id
WHERE 
	so.type = ''U'' 
ORDER BY so.object_id')

SELECT @numtables = count(*) FROM #tables

--Get pre-reorg stats
	INSERT INTO #fragreport (	[ObjectName],
	[ObjectId] ,
	[IndexName]  ,
	[IndexId] ,
	database_id ,
	partition_number,	
	index_type_desc	,
	alloc_unit_type_desc ,	
	index_depth,	
	index_level ,
	avg_fragmentation_in_percent ,	
	fragment_count ,	
	avg_fragment_size_in_pages,	
	page_count ,	
	avg_page_space_used_in_percent,	
	record_count,	
	ghost_record_count,	
	version_ghost_record_count ,	
	min_record_size_in_bytes ,	
	max_record_size_in_bytes ,	
	avg_record_size_in_bytes  ,	
	forwarded_record_count ,	
	compressed_page_count ,	
	hobt_id ,
	columnstore_delete_buffer_state,	
	columnstore_delete_buffer_state_desc ,	
	version_record_count ,	
	inrow_version_record_count ,	
	inrow_diff_version_record_count ,	
	total_inrow_version_payload_size_in_bytes ,	
	offrow_regular_version_record_count ,	
	offrow_long_term_version_record_count 
)
EXEC('USE ' + @dbname + ' SELECT 
    OBJECT_NAME(idx.object_id) AS ObjectName,
    idx.object_id as ObjectID,
    idx.name AS IndexName,
    idxps.index_id as IndexId,
    idxps.database_id, 
    idxps.partition_number, 
    idxps.index_type_desc, 
    idxps.alloc_unit_type_desc, 
    idxps.index_depth, 
    idxps.index_level, 
    idxps.avg_fragmentation_in_percent, 
    idxps.fragment_count, 
    idxps.avg_fragment_size_in_pages, 
    idxps.page_count, 
    idxps.avg_page_space_used_in_percent, 
    idxps.record_count, 
    idxps.ghost_record_count, 
    idxps.version_ghost_record_count, 
    idxps.min_record_size_in_bytes, 
    idxps.max_record_size_in_bytes, 
    idxps.avg_record_size_in_bytes, 
    idxps.forwarded_record_count, 
    idxps.compressed_page_count, 
    idxps.hobt_id, 
    idxps.columnstore_delete_buffer_state,	
    idxps.columnstore_delete_buffer_state_desc, 
    idxps.version_record_count, 
    idxps.inrow_version_record_count, 
    idxps.inrow_diff_version_record_count, 
    idxps.total_inrow_version_payload_size_in_bytes, 
    idxps.offrow_regular_version_record_count, 
    idxps.offrow_long_term_version_record_count
FROM 
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS idxps
INNER JOIN 
    sys.indexes AS idx ON idx.object_id = idxps.object_id AND idx.index_id = idxps.index_id;')

	DELETE FROM #fragreport
	WHERE IndexID IN (0,255)

	UPDATE #fragreport
	SET PrePost = 'PRE'
	WHERE PrePost is NULL

WHILE @tabcount <= @numtables
BEGIN


	SELECT @currtable = tabid,
	       @tabname = ltrim(rtrim([name])),
		   @schemaname = ltrim(rtrim(schemaname)) 
	FROM #tables
	WHERE rid = @tabcount 
	
	EXEC ('USE ' + @dbname + ' ALTER INDEX ALL ON '+@schemaname+'.['+@tabname+'] REORGANIZE') -- Do a basic reorg on all indexes on the table

	EXEC ('USE ' + @dbname + ' UPDATE STATISTICS '+@schemaname+'.['+@tabname+'] with FULLSCAN') -- And update statistics

	SET @tabcount = @tabcount + 1
END --reorg all indexes on all tables

INSERT INTO #fragreport (	[ObjectName],
	[ObjectId] ,
	[IndexName]  ,
	[IndexId] ,
	database_id ,
	partition_number,	
	index_type_desc	,
	alloc_unit_type_desc ,	
	index_depth,	
	index_level ,
	avg_fragmentation_in_percent ,	
	fragment_count ,	
	avg_fragment_size_in_pages,	
	page_count ,	
	avg_page_space_used_in_percent,	
	record_count,	
	ghost_record_count,	
	version_ghost_record_count ,	
	min_record_size_in_bytes ,	
	max_record_size_in_bytes ,	
	avg_record_size_in_bytes  ,	
	forwarded_record_count ,	
	compressed_page_count ,	
	hobt_id ,
	columnstore_delete_buffer_state,	
	columnstore_delete_buffer_state_desc ,	
	version_record_count ,	
	inrow_version_record_count ,	
	inrow_diff_version_record_count ,	
	total_inrow_version_payload_size_in_bytes ,	
	offrow_regular_version_record_count ,	
	offrow_long_term_version_record_count 
)
EXEC('USE ' + @dbname + ' SELECT 
    OBJECT_NAME(idx.object_id) AS ObjectName,
    idx.object_id as ObjectID,
    idx.name AS IndexName,
    idxps.index_id as IndexId,
    idxps.database_id, 
    idxps.partition_number, 
    idxps.index_type_desc, 
    idxps.alloc_unit_type_desc, 
    idxps.index_depth, 
    idxps.index_level, 
    idxps.avg_fragmentation_in_percent, 
    idxps.fragment_count, 
    idxps.avg_fragment_size_in_pages, 
    idxps.page_count, 
    idxps.avg_page_space_used_in_percent, 
    idxps.record_count, 
    idxps.ghost_record_count, 
    idxps.version_ghost_record_count, 
    idxps.min_record_size_in_bytes, 
    idxps.max_record_size_in_bytes, 
    idxps.avg_record_size_in_bytes, 
    idxps.forwarded_record_count, 
    idxps.compressed_page_count, 
    idxps.hobt_id, 
    idxps.columnstore_delete_buffer_state,	
    idxps.columnstore_delete_buffer_state_desc, 
    idxps.version_record_count, 
    idxps.inrow_version_record_count, 
    idxps.inrow_diff_version_record_count, 
    idxps.total_inrow_version_payload_size_in_bytes, 
    idxps.offrow_regular_version_record_count, 
    idxps.offrow_long_term_version_record_count
FROM 
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS idxps
INNER JOIN 
    sys.indexes AS idx ON idx.object_id = idxps.object_id AND idx.index_id = idxps.index_id;')

	DELETE FROM #fragreport
	WHERE IndexID IN (0,255)

	UPDATE #fragreport
	SET PrePost = 'POST'
	WHERE PrePost is NULL

if @catswitch > 0
begin
	SET @catcount = 1

	EXEC('INSERT INTO #catalogs (catname)
		SELECT 
			[name]
		FROM '
		+@dbname+'.sys.fulltext_catalogs')

	SELECT
		@numcats = count(*)
	FROM
		#catalogs

	WHILE @catcount <= @numcats
	BEGIN
		SELECT
			@catname = catname
		From
			#catalogs
		WHERE cid = @catcount

		if @catswitch = 1
			EXEC('USE ' + @dbname + ' ALTER FULLTEXT CATALOG '+ @catname+' REORGANIZE')
		ELSE IF @catswitch = 2
			EXEC('USE ' + @dbname + ' ALTER FULLTEXT CATALOG '+ @catname+' REBUILD')
		SET @catcount = @catcount + 1

	END -- catalog looping
END --@catswitch > 0

--find the indexes that are still fragmented after the reorg

INSERT INTO #reindex([ObjectName],[IndexName], [SchemaName], [ObjectID], [IndexID])
SELECT #tables.[name], #fragreport.[IndexName], #tables.schemaname, #fragreport.ObjectId, #fragreport.indexid
FROM #fragreport
INNER JOIN #tables on #tables.tabid = #fragreport.objectid
WHERE #fragreport.IndexId NOT IN (0, 255)
AND (#fragreport.avg_fragment_size_in_pages < @FragPages OR #fragreport.avg_fragmentation_in_percent > @FragPercent) 
AND #fragreport.PrePost = 'POST'

SELECT @numreindexes = count(*) FROM #reindex

SET @recount = 1

WHILE @recount <= @numreindexes
BEGIN

    DECLARE @object varchar(50),
			@index varchar(50)

	SELECT @tabname = ObjectName,
	       @indname = IndexName,
		   @schemaname = SchemaName,
		   @object = CAST(ObjectID as varchar (50)),
		   @index = CAST(IndexID as varchar(50))
	FROM #reindex
	WHERE rid = @recount

	EXEC ('USE ' + @dbname + ' ALTER INDEX ['+@indname+'] ON '+@schemaname+'.['+@tabname+'] REBUILD')
	
	INSERT INTO #fragreport (	
	[ObjectName],
	[ObjectId] ,
	[IndexName]  ,
	[IndexId] ,
	database_id ,
	partition_number,	
	index_type_desc	,
	alloc_unit_type_desc ,	
	index_depth,	
	index_level ,
	avg_fragmentation_in_percent ,	
	fragment_count ,	
	avg_fragment_size_in_pages,	
	page_count ,	
	avg_page_space_used_in_percent,	
	record_count,	
	ghost_record_count,	
	version_ghost_record_count ,	
	min_record_size_in_bytes ,	
	max_record_size_in_bytes ,	
	avg_record_size_in_bytes  ,	
	forwarded_record_count ,	
	compressed_page_count ,	
	hobt_id ,
	columnstore_delete_buffer_state,	
	columnstore_delete_buffer_state_desc ,	
	version_record_count ,	
	inrow_version_record_count ,	
	inrow_diff_version_record_count ,	
	total_inrow_version_payload_size_in_bytes ,	
	offrow_regular_version_record_count ,	
	offrow_long_term_version_record_count 
)
EXEC('USE ' + @dbname + ' SELECT 
    OBJECT_NAME(idx.object_id) AS ObjectName,
    idx.object_id as ObjectID,
    idx.name AS IndexName,
    idxps.index_id as IndexId,
    idxps.database_id, 
    idxps.partition_number, 
    idxps.index_type_desc, 
    idxps.alloc_unit_type_desc, 
    idxps.index_depth, 
    idxps.index_level, 
    idxps.avg_fragmentation_in_percent, 
    idxps.fragment_count, 
    idxps.avg_fragment_size_in_pages, 
    idxps.page_count, 
    idxps.avg_page_space_used_in_percent, 
    idxps.record_count, 
    idxps.ghost_record_count, 
    idxps.version_ghost_record_count, 
    idxps.min_record_size_in_bytes, 
    idxps.max_record_size_in_bytes, 
    idxps.avg_record_size_in_bytes, 
    idxps.forwarded_record_count, 
    idxps.compressed_page_count, 
    idxps.hobt_id, 
    idxps.columnstore_delete_buffer_state,	
    idxps.columnstore_delete_buffer_state_desc, 
    idxps.version_record_count, 
    idxps.inrow_version_record_count, 
    idxps.inrow_diff_version_record_count, 
    idxps.total_inrow_version_payload_size_in_bytes, 
    idxps.offrow_regular_version_record_count, 
    idxps.offrow_long_term_version_record_count
FROM 
    sys.dm_db_index_physical_stats(DB_ID(), ' + @object + ', ' + @index + ', NULL, ''LIMITED'') AS idxps
INNER JOIN 
    sys.indexes AS idx ON idx.object_id = idxps.object_id AND idx.index_id = idxps.index_id;')

	SET @recount = @recount + 1
END -- rebuild loop



UPDATE #fragreport
SET PrePost = 'REBUILT'
WHERE PrePost is NULL

UPDATE #fragreport
SET DBName = @dbname

INSERT INTO [TestDB].[dbo].[fragreport] --change master here to where the fragreport DB is actually located
	([TimeProc], 
	[ObjectName],
	[ObjectId] ,
	[IndexName]  ,
	[IndexId] ,
	database_id ,
	partition_number,	
	index_type_desc	,
	alloc_unit_type_desc ,	
	index_depth,	
	index_level ,
	avg_fragmentation_in_percent ,	
	fragment_count ,	
	avg_fragment_size_in_pages,	
	page_count ,	
	avg_page_space_used_in_percent,	
	record_count,	
	ghost_record_count,	
	version_ghost_record_count ,	
	min_record_size_in_bytes ,	
	max_record_size_in_bytes ,	
	avg_record_size_in_bytes  ,	
	forwarded_record_count ,	
	compressed_page_count ,	
	hobt_id ,
	columnstore_delete_buffer_state,	
	columnstore_delete_buffer_state_desc ,	
	version_record_count ,	
	inrow_version_record_count ,	
	inrow_diff_version_record_count ,	
	total_inrow_version_payload_size_in_bytes ,	
	offrow_regular_version_record_count ,	
	offrow_long_term_version_record_count ,
	[DBName], 
	[PrePost])
SELECT 
	[TimeProc], 
	[ObjectName],
	[ObjectId] ,
	[IndexName]  ,
	[IndexId] ,
	database_id ,
	partition_number,	
	index_type_desc	,
	alloc_unit_type_desc ,	
	index_depth,	
	index_level ,
	avg_fragmentation_in_percent ,	
	fragment_count ,	
	avg_fragment_size_in_pages,	
	page_count ,	
	avg_page_space_used_in_percent,	
	record_count,	
	ghost_record_count,	
	version_ghost_record_count ,	
	min_record_size_in_bytes ,	
	max_record_size_in_bytes ,	
	avg_record_size_in_bytes  ,	
	forwarded_record_count ,	
	compressed_page_count ,	
	hobt_id ,
	columnstore_delete_buffer_state,	
	columnstore_delete_buffer_state_desc ,	
	version_record_count ,	
	inrow_version_record_count ,	
	inrow_diff_version_record_count ,	
	total_inrow_version_payload_size_in_bytes ,	
	offrow_regular_version_record_count ,	
	offrow_long_term_version_record_count ,
	[DBName], 
	[PrePost] 
FROM 
	#fragreport

DROP TABLE #tables
DROP TABLE #fragreport
DROP TABLE #reindex
DROP TABLE #catalogs


GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO





