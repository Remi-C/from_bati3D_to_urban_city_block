---------------
--- Script by Rémi Cura
-- thales ign , 2015

-- converting a partial export of bati3D 3DS file to a building layout and regouping it into building blocks
--------------



CREATE EXTENSION IF NOT EXISTS postgis ;

CREATE EXTENSION IF NOT EXISTS plpythonu ; 
CREATE EXTENSION IF NOT EXISTS rc_lib_postgres ; 
CREATE EXTENSION IF NOT EXISTS rc_lib_postgis ; 


CREATE SCHEMA IF NOT EXISTS converting ; 
SET search_path to converting, public ; 



--importing the data from a csv file
--creating table to hold data

	DROP TABLE IF EXISTS paris_6_3DS; 
	CREATE TABLE paris_6_3DS (
		--gid SERIAL PRIMARY KEY
		 nomBatimentComposite text
		, nomBatimentSimple text
		,nomMesh text
		, x1 float
		,y1 float
		,x2 float
		,y2 float
		--, geom geometry(linestring,931008)
	); 


SELECT *
FROM public.spatial_ref_sys
WHERE srtext ILIKE '%LAMB93%'
LIMIT 1
COPY FROM '/tmp/miloud.csv' TO 


COPY paris_6_3DS
FROM '/tmp/export_3DS_paris_6.csv'
 CSV HEADER DELIMITER ' ' ;


 SELECT *
 FROM paris_6_3ds 
 LIMIT 1 ; 

DROP TABLE IF EXISTS v  ; 
 CREATE TABLE paris_6_geom (
	gid serial primary key
	,  nomBatimentComposite text
	, nomBatimentSimple text
	,nomMesh text
	, x1 float
	,y1 float
	,x2 float
	,y2 float
	, point1 geometry(point,931008)
	, point2 geometry(point,931008)
	, line geometry(linestring,931008) 
 ) ; 

CREATE INDEX ON paris_6_geom USING gist(point1) ;  
CREATE INDEX ON paris_6_geom USING gist(point2) ;  
CREATE INDEX ON paris_6_geom USING gist(line) ; 




	

INSERT INTO paris_6_geom ( nomBatimentComposite, nomBatimentSimple, nomMesh,  x1  ,y1  ,x2 ,y2  , point1, point2,line ) 
	SELECT nomBatimentComposite, nomBatimentSimple, nomMesh,  x1  ,y1  ,x2 ,y2  
	,ST_SetSRID(ST_MakePoint( x1,y1), 931008)
	,ST_SetSRID(ST_MakePoint( x2,y2), 931008)
	, ST_SetSRID(ST_MakeLine(ST_MakePoint( x1,y1) , ST_MakePoint( x2,y2) ) , 931008)
	 
	FROM  paris_6_3ds; 




--note : utiliser enveloppe convex sur les points pour montrer

	DROP TABLE convex_enveloppe ; 
	CREATE TABLE convex_enveloppe AS 
	SELECT 	row_number() over() as nid, 	St_Multi(ST_CollectionExtract(ST_ConcaveHull(st_collect(point1),0.5,false),3))::geometry(multipolygon,931008) AS convex_hull
	FROM paris_6_geom
	GROUP BY nomBatimentComposite ; 

	SELECT ST_AsText(convex_hull)
	FROM convex_enveloppe ;


	DROP TABLE IF EXISTS  makeline ; 
	CREATE TABLE makeline AS 
	SELECT row_number() over() as uid,  ST_makeLine(line ORDER BY gid)::geometry(linestring,931008) AS geom 
	FROM paris_6_geom
	GROUP BY nomBatimentSimple ;

	DROP TABLE IF EXISTS polygonize ; 
	CREATE TABLE polygonize AS 
	SELECT uid, St_Multi(ST_CollectionExtract(ST_Polygonize(geom),3)) ::geometry(multipolygon,931008)as poly
	FROM makeline
	GROUP BY uid ;

	
	SELECT ST_ASText(geom) 
	FROM makeline ;


	DROP TABLE IF EXISTS buildarea ; 
	CREATE TABLE buildarea AS 
	SELECT  row_number() over( ) as uid   , St_Multi(ST_CollectionExtract(ST_BuildArea(St_Collect(line) ) ,3)) ::geometry(multipolygon,931008) AS barea
	FROM paris_6_geom 
	GROUP BY nomBatimentSimple ;

	CREATE INDEX ON buildarea USING GIST ( barea )  ;
	CREATE INDEX ON buildarea   ( uid )  ; 

--clustering  ! grouping building layout into city blocks

DROP TABLE IF EXISTS matching  ; 
CREATE TABLE matching AS 

SELECT row_number() over() as qgisid, b1.uid AS uid1, b2.uid AS uid2, St_Multi(ST_Union(b1.barea, b2.barea))::geometry(multipolygon,931008) as u
FROM buildarea AS b1
	, buildarea AS b2
WHERE b1.uid < b2.uid
	AND ST_DWithin(b1.barea, b2.barea, 0.1) = TRUE ; 

	--now use rc_py_connected_components
	-- onnected compoentzs : way to go <ith non trivial distances

DROP TABLE IF EXISTS ccomponents ; 
CREATE TABLE ccomponents AS 
WITH agg_data AS (
SELECT array_agg(uid1::int ORDER BY qgisid) as ag1, array_agg(uid2::int ORDER BY qgisid) AS ag2
FROM matching 
)
, results AS (
SELECT r.node AS uid, r.ccomponents
FROM agg_data, rc_lib . rc_py_ccomponents(ag1 ,  ag2 )  AS r

)
--do something with building block, here union of buffer
SELECT ccomponents, ST_Buffer(ST_Union(ST_Buffer(b.barea,1)),-1) AS final_building_blocks
FROM results LEFT OUTER JOIN buildarea AS b USING (uid)
GROUP BY ccomponents



DROP TABLE IF EXISTS super_area  ;
CREATE TABLE super_area AS 

	WITH barea AS (
		SELECT St_Multi(
					ST_CollectionExtract(
						st_buildarea(
							ST_Node(
								ST_Collect(
									ST_ExteriorrING(
										ST_Buffer(line,0.1,'quad_segs=4')
									)
								)
							)
						)
					,3 ) 
					) ::geometry(multipolygon,931008) AS barea
		FROM paris_6_geom
		)
	SELECT row_number() over() as qgisid  , St_Multi(ST_CollectionExtract(dmp.geom,3) )::geometry(multipolygon,931008) AS barea
	FROM barea , ST_Dump(barea) As dmp



	

