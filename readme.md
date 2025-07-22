# Prepare database 

## Download and prepare RNB 
```sh
cd import
mkdir working_dir
cd working_dir
wget https://rnb-opendata.s3.fr-par.scw.cloud/files/RNB_nat.csv.zip
unzip RNB_nat.csv.zip
rm RNB_nat.csv.zip
gawk -v FPAT='("([^"]*)")|[^;]+' -v OFS=';' 'NR==1 || NF { print $1, $3 }'  RNB_nat.csv > RNB_nat_.csv  && mv RNB_nat_.csv  RNB_nat.csv
```

## Create the RNB table


```sh
CREATE TABLE rnb_buildings (
    rnb_id TEXT PRIMARY KEY NOT NULL,
    code_insee TEXT,
    shape geometry(GEOMETRY, 4326) NOT NULL
);

CREATE INDEX idx_rnb_buildings_code_insee ON rnb_buildings (code_insee);

CREATE INDEX idx_rnb_buildings_shape ON rnb_buildings USING GIST (shape);

```

## Import RNB in database
```sql
COPY rnb_buildings(rnb_id, shape) FROM '{working-dir}/import/working_dir/RNB_nat.csv' WITH (FORMAT CSV, DELIMITER ';', HEADER TRUE, ENCODING 'UTF8');
```

## Import OSM buildings from a osm2pgsql database

Can take up to 1h30 mins

```sql
./building.sql
```

## Compute RNB matching

Take like 4h30 mins

```sh
$ compute_rnb_matching.sh
```

## You can setup a cron to compute rnb matching

Execute the script periodically `compute_rnb_matching.sql`

# Run the vector tile server

```sh
docker compose up 
```