
Setup the python env

```python
python -m venv venv
source venv/bin/activate
pip install -U pip
pip install -r requirements.txt

```
<!-- RNB_DOWNLOAD_LINK = "https://rnb-opendata.s3.fr-par.scw.cloud/files/RNB_nat.csv.zip" -->

```sh
cd import
mkdir working_dir
cd working_dir
wget https://rnb-opendata.s3.fr-par.scw.cloud/files/RNB_nat.csv.zip
unzip RNB_nat.csv.zip
rm RNB_nat.csv.zip
csvcut -d ';' -c rnb_id,shape RNB_nat.csv > RNB_nat_.csv && mv RNB_nat_.csv  RNB_nat.csv
```

In psql:

IF rnb_buildings already exists, you can skip this part
```sh
CREATE TABLE rnb_buildings (
    rnb_id TEXT PRIMARY KEY NOT NULL,
    code_insee TEXT,
    shape geometry(GEOMETRY, 4326) NOT NULL
);

CREATE INDEX idx_rnb_buildings_code_insee ON rnb_buildings (code_insee);

CREATE INDEX idx_rnb_buildings_shape ON rnb_buildings USING GIST (shape);

```

IF extracted_buildings already have matching rnb fields, you can skip this part
```sql
ALTER TABLE extracted_buildings
ADD COLUMN match_rnb_ids TEXT,
ADD COLUMN match_rnb_score FLOAT,
ADD COLUMN match_rnb_diff TEXT;

```


```sql
COPY rnb_buildings(rnb_id, shape) FROM '{current_dir}/import/working_dir/RNB_nat.csv' WITH (FORMAT CSV, DELIMITER ',', HEADER TRUE, ENCODING 'UTF8');
```


```sql
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
```