
Setup the python env

```python
python -m venv venv
source venv/bin/activate
pip install -U pip
pip install -r requirements.txt

```

```sh
cd import
mkdir working_dir
cd working_dir
wget https://rnb-opendata.s3.fr-par.scw.cloud/files/RNB_nat.csv.zip
unzip RNB_nat.csv.zip
rm RNB_nat.csv.zip
gawk -v FPAT='("([^"]*)")|[^;]+' -v OFS=';' 'NR==1 || NF { print $1, $3 }'  RNB_nat.csv > RNB_nat_.csv  && mv RNB_nat_.csv  RNB_nat.csv
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
COPY rnb_buildings(rnb_id, shape) FROM '/var/www/data-osm/osm-data-vector-tiles/import/working_dir/RNB_nat.csv' WITH (FORMAT CSV, DELIMITER ';', HEADER TRUE, ENCODING 'UTF8');
```

```sql
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_wall ON extracted_buildings (wall);
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_shelter_type ON extracted_buildings (shelter_type);
CREATE INDEX IF NOT EXISTS idx_extracted_buildings_type ON extracted_buildings (type);
```

```sql
./compute_rnb_matching.sql
```