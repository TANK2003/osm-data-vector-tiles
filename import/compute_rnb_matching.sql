UPDATE extracted_buildings SET
match_rnb_ids = subquery.rnb_ids,
match_rnb_score=subquery.score,
match_rnb_diff =subquery.diff
FROM
(
WITH recouvrement AS (
            SELECT DISTINCT osm.osm_id osm_id,
                osm.osm_type,
                rnb.rnb_id rnb_id,
                    CASE
                        WHEN st_isvalid(osm.way)
                            AND st_isvalid(rnb.shape)
                            AND st_area(st_intersection(osm.way, rnb.shape)) > 0::double precision
                            THEN st_area(st_intersection(osm.way, rnb.shape)) / LEAST(st_area(osm.way), st_area(rnb.shape)) * 100::double precision
                        ELSE 0::double precision
                    END AS pourcentage_recouvrement
            FROM extracted_buildings osm
                JOIN rnb_buildings rnb ON st_intersects(osm.way, rnb.shape)
            WHERE
                osm.wall != 'no'
                AND
                shelter_type != 'public_transport'
                AND
                type not in ('ruins','construction','static_caravan','ger','collapsed','no','tent','tomb','abandoned','mobile_home','proposed','destroyed','roof')                
                AND
                CASE
                    WHEN st_isvalid(osm.way)
                        AND st_isvalid(rnb.shape)
                        AND st_area(st_intersection(osm.way, rnb.shape)) > 0::double precision
                        THEN st_area(st_intersection(osm.way, rnb.shape)) / LEAST(st_area(osm.way), st_area(rnb.shape)) * 100::double precision
                    ELSE 0::double precision
                END > 70::double precision
        )
        SELECT
            r.osm_id,
            r.osm_type,
            string_agg(r.rnb_id::text, '; '::text) AS rnb_ids,
            round(avg(r.pourcentage_recouvrement)) / 100::double precision AS score,
                CASE
                    WHEN length(string_agg(r.rnb_id::text, '; '::text)) > 12 THEN 'multiple'::text
                    ELSE NULL::text
                END AS diff
        FROM ( SELECT r_1.osm_id,
                    r_1.osm_type,
                    r_1.rnb_id,
                    r_1.pourcentage_recouvrement
                FROM recouvrement r_1
                WHERE NOT (r_1.rnb_id::text IN ( SELECT r_2.rnb_id
                        FROM recouvrement r_2
                        GROUP BY r_2.rnb_id
                        HAVING POSITION((';'::text) IN (string_agg(r_2.osm_id::text, '; '::text))) > 0))) r
        GROUP BY r.osm_id,r.osm_type
        UNION
        SELECT
            r.osm_id,
            r.osm_type,
            r.rnb_id AS rnb_ids,
            round(r.pourcentage_recouvrement) / 100::double precision AS score,
            'splited'::text AS diff
        FROM recouvrement r
        WHERE (r.rnb_id::text IN ( SELECT r_1.rnb_id
                FROM recouvrement r_1
                GROUP BY r_1.rnb_id
                HAVING POSITION((';'::text) IN (string_agg(r_1.osm_id::text, '; '::text))) > 0))

	) as subquery
WHERE subquery.osm_id=extracted_buildings.osm_id
	;