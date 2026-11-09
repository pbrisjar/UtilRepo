--Created to run validity checks against the ntext columns.
--Note that running this has, in tests, taken a long time

Create table #TextvalidCheck 
	( tvid int identity (1,1),
	ColName	sysname,
	data nvarchar(max),
	ValidCheck int)


--INSERT INTO #TextvalidCheck (ColName,data,ValidCheck) SELECT 'Testcol', Testcol, TEXTVALID ('t2.testcol', TEXTPTR(testcol)) FROM t2 WHERE TEXTVALID ('t2.Testcol', TEXTPTR(Testcol)) = 0
INSERT INTO #TextvalidCheck (ColName,data,ValidCheck) SELECT 'Testcol2', Testcol2, TEXTVALID ('t2.Testcol2', TEXTPTR(Testcol2)) FROM t2 --WHERE TEXTVALID ('t2.testcol2', TEXTPTR(Testcol2)) = 0

Select * from  #TextvalidCheck 

--DROP TABLE #TextvalidCheck 