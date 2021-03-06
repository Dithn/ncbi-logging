#!/bin/bash

# shellcheck source=/home/vartanianmh/strides/strides_env.sh
. "$HOME/strides/strides_env.sh"

cd "$PANFS/export" || exit

# Attempt to pin DB to RAM
tar -cf - $PGDATA > /dev/zero 2>&1 &

psql -h localhost -d grafana -X << HERE
    DROP TABLE IF EXISTS export;
    CREATE UNLOGGED TABLE export (
    status text,
    ip text,
    host text,
    cmds text,
    bytecount bigint,
    agent text,
    cnt bigint,
    acc text,
    start_ts timestamp,
    end_ts timestamp,
    source text,
    ip_int double precision
);

    DROP TABLE IF EXISTS export_objects;
    CREATE UNLOGGED TABLE export_objects (data jsonb);
HERE

# export.20190822.000000000024.csv.gz
if [ ! -s export."$YESTERDAY".000000000015.csv.gz ]; then
    echo "No exports present, aborting"
    exit 1
fi

# NOTE: Not profitable to do this in parallel, some kind of contention
for x in export."$YESTERDAY".*.gz; do
    echo "Loading $x"
    psql -h localhost -d grafana -c \
        "\\copy export FROM program 'zcat $x' FORCE NOT NULL acc CSV HEADER;"
done

for x in "$PANFS/gs_prod/objects/$YESTERDAY."*gz "$PANFS/s3_prod/objects/$YESTERDAY."*gz  ; do
    echo "Loading $x"
    psql -h localhost -d grafana -c \
        "\\copy export_objects FROM program 'zcat $x';"
done

echo "Loaded exports"

time psql -h localhost -d grafana << HERE
SELECT count(*) AS export_count FROM export;
SELECT count(*) AS export_objects FROM export_objects;

DROP TABLE IF EXISTS objects_load;
--CREATE TABLE objects_load ( acc text, export_time timestamp, load_time timestamp, etag text, bytecount bigint, bucket text, source text, last_modified timestamp, storage_class text, md5 text);

CREATE TABLE objects_load as SELECT
--INSERT INTO objects_load SELECT
    data->>'key' AS acc,
    TO_TIMESTAMP(data->>'now','YYYY-MM-DD HH24:MI:SS') AS export_time,
    now() as load_time,
    data->>'etag' AS etag,
    cast(data->>'size' AS bigint) AS bytecount,
    data->>'bucket' AS bucket,
    data->>'source' AS source,
    TO_TIMESTAMP(data->>'lastmodified','YYYY-MM-DD HH24:MI:SS') AS last_modified,
    data->>'storageclass' AS storage_class,
    data->>'md5' as md5
    from export_objects;
DROP TABLE export_objects;

BEGIN;
    DROP TABLE IF EXISTS objects_uniq;
    ALTER TABLE cloud_objects RENAME to objects_uniq;

--  DROP TABLE IF EXISTS cloud_objects;
    CREATE TABLE cloud_objects AS
        SELECT acc, etag, bytecount, bucket, source, storage_class, md5, last_modified,
        MIN(export_time) AS export_time,
        MAX(load_time) AS load_time
        FROM (
            SELECT acc, etag, bytecount, bucket, source, storage_class, md5, last_modified,
            export_time, load_time
            FROM objects_load
            UNION ALL
            SELECT acc, etag, bytecount, bucket, source, storage_class, md5, last_modified,
            export_time, load_time
            FROM objects_uniq ) as f
        GROUP by acc, etag, bytecount, bucket, source, storage_class, md5, last_modified;
    DROP TABLE objects_load;
    DROP TABLE objects_uniq;
END;
SELECT COUNT(*) AS Cloud_Objects from cloud_objects;


CREATE TEMP TABLE ips_export AS SELECT distinct ip, ip_int
    FROM export
    WHERE ip_int > 0;

DROP TABLE IF EXISTS ips_export2;
CREATE TABLE ips_export2 as
    SELECT ips_export.ip, ip_int, domain, city_name, country_code
    FROM ips_export, ip2location_db11_ipv4, rdns
    WHERE
        BOX(POINT(ip_FROM, ip_FROM), POINT(ip_to, ip_to)) @>
        BOX(POINT (ip_int, ip_int), POINT(ip_int, ip_int))
        AND rdns.ip=ips_export.ip ;

SELECT count(*) AS ips_export2_count FROM ips_export2;

CREATE INDEX ips_export2_ip on ips_export2(ip);
CREATE INDEX ips_export2_ipint on ips_export2(ip_int);


DROP TABLE IF EXISTS export_joined;
CREATE TABLE export_joined as
    SELECT status, cmds, bytecount,
        agent, cnt, acc, start_ts, end_ts, source,
        host,
        city_name, country_code, domain,
        export.ip, export.ip_int
    FROM export, ips_export2
    WHERE
        export.ip_int=ips_export2.ip_int
    ORDER BY source, start_ts;

DROP TABLE export;

SELECT count(*) AS export_joined_count FROM EXPORT_JOINED;

BEGIN;
-- Closest thing to an atomic swap of table
    ALTER TABLE cloud_sessions RENAME TO cloud_sessions_bak;
    ALTER TABLE export_joined RENAME TO cloud_sessions;
COMMIT;
DROP TABLE IF EXISTS cloud_sessions_bak;

SELECT count(*) AS cloud_sessions_count FROM cloud_sessions;

DROP index cloud_sessions_start;
DROP index cloud_sessions_source;
CREATE index cloud_sessions_start on cloud_sessions (start_ts);
CREATE index cloud_sessions_source on cloud_sessions (source);

-- Fix: IP2LOCATION gets this very wrong
update cloud_sessions set city_name='Mountain View', country_code='US'
where ip like '35.245.%';


-- Create materialized views, AS tables in case we need to index them
BEGIN;
    DROP TABLE IF EXISTS last_used;
    CREATE TABLE last_used as
        SELECT acc, max(last) AS last
        FROM  (
            SELECT acc, date_trunc('day', start_ts) AS last
            FROM cloud_sessions
            where source='SRA'
            and acc ~ '[DES]RR[\d\.]{6,10}'
            union all
            SELECT run AS acc, '2018-06-01 00:00:00'::timestamp AS last
            FROM public
        ) AS roll2
        group by acc;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS last_used_interval;
    CREATE TABLE last_used_interval as
    SELECT case
        when date_trunc('day', age(localtimestamp, last)) < interval '30 days'
        then 'downloaded in last 30 days'
        when date_trunc('day', age(localtimestamp, last)) > interval '180 days'
        then 'never downloaded'
        else 'downloaded 30..180 days ago'
    end AS metric,
    count(*) AS value
    FROM last_used
    group by metric;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS downloads_by_ip;
    CREATE TABLE downloads_by_ip as
        SELECT date_trunc('day', start_ts) AS time,
        source,
        count(distinct ip) AS unique_users
        FROM
        cloud_sessions
        WHERE
        ( cmds like '%GET%' or cmds like '%HEAD%' )
        AND source != 'SRA'
        GROUP BY time, source
        ORDER BY time;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS daily_downloads;
    CREATE TABLE daily_downloads as
    SELECT
        date_trunc('day', start_ts) AS time,
        source,
        sum(bytecount) AS bytes,
        count(*) AS downloads
    FROM
        cloud_sessions
    WHERE
        ( cmds like '%GET%' or cmds like '%HEAD%' )
    AND domain not like '%nih.gov%'
    GROUP BY "time", source
    ORDER BY "time";
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS cloud_downloads;
    CREATE TABLE cloud_downloads AS
    SELECT source || ' -> ' || domain
    || ' @ ' || city_name
    || ', ' || country_code
    AS Path,
    count(*) AS Downloads, sum(bytecount) AS Bytes,
    date_trunc('day', start_ts) AS time
    FROM cloud_sessions
    where
    ( cmds like '%GET%' or cmds like '%HEAD%' )
    AND source!='SRA'
    group by time, path;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS sra_cloud;
    CREATE TABLE sra_cloud AS
    SELECT * from cloud_sessions
    WHERE source='SRA';
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS download_domains;
    CREATE TABLE download_domains AS
    SELECT DOMAIN,
        date_trunc('day',
                    start_ts) AS TIME,
        sum(bytecount) AS Bytes
    FROM sra_cloud
    GROUP BY DOMAIN, TIME;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS sra_cloud_downloads;
    CREATE TABLE sra_cloud_downloads as
    SELECT
        date_trunc('day', start_ts) AS time,
        sum(bytecount) AS bytes,
        count(*) AS downloads
    FROM
        sra_cloud
    GROUP BY "time";
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS cloud_organisms;
    CREATE TABLE cloud_organisms as
        SELECT initcap(scientificname) as Organism,
        count(*) AS popularity,
        date_trunc('day', start_ts) AS time
        FROM cloud_sessions, public
        where
        ( cmds like '%GET%' or cmds like '%HEAD%' )
        AND cloud_sessions.acc=run
        group by time, Organism
        order by popularity desc
        limit 500;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS acc_last_acc;
    CREATE TABLE acc_last_acc as
    SELECT last AS time, count(*) AS accessions FROM (
    SELECT max(last) AS last
    FROM last_used
    group by acc) AS roll
    group by last
    order by last;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS sra_agents;
    CREATE TABLE sra_agents AS
    SELECT
    source,
    date_trunc('day', start_ts) AS time,
    substr(agent,0,40) AS agent,
    sum(bytecount) AS bytes
    FROM cloud_sessions
    GROUP BY source, time, agent
    ORDER BY time, source, agent;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS last_used_cost;
    CREATE TABLE last_used_cost AS
    SELECT
    SUM(CAST (size_mb AS INTEGER))/1024.0 AS gb,
    case
        when date_trunc('day', age(localtimestamp, last)) < interval '30 days'
        then 'downloaded in last 30 days'
        when date_trunc('day', age(localtimestamp, last)) > interval '180 days'
        then 'never downloaded'
        else 'downloaded 30..180 days ago'
    END AS metric
    FROM LAST_USED, PUBLIC
    WHERE
    LAST_USED.ACC=PUBLIC.RUN
    AND TO_TIMESTAMP(PUBLIC.RELEASEDATE,'YYYY-MM-DD HH24:MI:SS') <
    CURRENT_DATE - INTERVAL '180 DAYS'
    GROUP BY METRIC;

    DROP TABLE IF EXISTS storage_cost;
    CREATE TABLE storage_cost (class text, savings double precision);
    INSERT INTO storage_cost
        SELECT 'Nearline/Infrequent' AS class,
        gb*2.5
        FROM last_used_cost
        WHERE metric='never downloaded';

    INSERT INTO storage_cost
        SELECT 'Coldline/Glacier' AS class,
        gb*3.6
        FROM last_used_cost
        WHERE metric='never downloaded';

    INSERT INTO storage_cost
        SELECT 'Coldline/Glacier Deep' AS class,
        gb*3.91
        FROM last_used_cost
        WHERE metric='never downloaded';
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS OBJECT_SIZES;
    CREATE TABLE OBJECT_SIZES AS
        SELECT lower(SOURCE) || '://' || BUCKET AS LOCATION,
        SUM(BYTECOUNT) AS BYTES
        FROM CLOUD_OBJECTS
        WHERE LOAD_TIME=(SELECT MAX(LOAD_TIME) FROM CLOUD_OBJECTS)
        GROUP BY LOCATION
        ORDER BY LOCATION;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS OBJECT_LOAD;
    CREATE TABLE OBJECT_LOAD AS
        SELECT date_trunc('day', last_modified) as time,
        count(*) as num_accessions,
        sum(bytecount) as bytes_uploaded
        from cloud_objects
        group by time
        order by time;
COMMIT;

BEGIN;
    CREATE TEMP TABLE public_dt AS SELECT
        run,
        TO_TIMESTAMP(PUBLIC.RELEASEDATE,'YYYY-MM-DD HH24:MI:SS') as released
    FROM PUBLIC
    WHERE releasedate > '2018-06-01';

    CREATE TEMP TABLE last_download as
        SELECT acc, max(last) AS last
        FROM  (
            SELECT acc, date_trunc('day', start_ts) AS last
            FROM cloud_sessions
            where source='SRA'
            and acc ~ '[DES]RR[\d\.]{6,10}'
            AND domain not like '%nih.gov%'
        UNION ALL
            SELECT run AS acc, '2018-06-01 00:00:00'::timestamp AS last
            FROM public
        ) AS roll2
        group by acc;

    CREATE TEMP TABLE last_dt AS SELECT
    substring(acc from '[DES]RR\w+') as acc, last
    from last_download
    where acc ~ '[DES]RR\w+';

    CREATE TEMP TABLE mean_time_use AS
    SELECT last_dt.acc as acc, last, released, last - released as delay
    FROM public_dt, last_dt
    WHERE public_dt.run=last_dt.acc;

    DROP TABLE IF EXISTS mean_latency;
    CREATE TABLE mean_latency AS
    SELECT AVG(delay) as mean_delay from mean_time_use where delay > '0 days';
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS blast_and_strides;
    CREATE TABLE blast_and_strides as
    SELECT domain, city_name, country_code, COUNT(*) as downloads
    FROM cloud_sessions
    WHERE ip in (SELECT DISTINCT ip FROM blast_sessions )
    GROUP BY domain, city_name, country_code
    ORDER by downloads desc;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS etag_delta;

    CREATE TABLE etag_delta as
    select distinct acc, etag, bytecount, last_modified
    from cloud_objects where acc in (
        select acc
        from cloud_objects
        where acc not like '%.vdbcache.%'
        group by acc
        having count(distinct etag) > 1 )
    order by acc asc, last_modified desc;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS egress;

    CREATE TABLE egress AS
    SELECT date_trunc('day', start_ts) AS TIME,
        SOURCE,
        DOMAIN,
        sum(bytecount) AS bytes
    FROM cloud_sessions
    WHERE (cmds LIKE '%GET%'
        OR cmds LIKE '%HEAD%')
    AND (cmds NOT LIKE '%POST%'
        AND cmds NOT LIKE '%PUT%')
    AND SOURCE IN ('GS',
                    'S3')
    AND ((SOURCE='S3'
            AND DOMAIN NOT LIKE '%(AWS Amazon)%')
        OR (SOURCE='GS'
            AND DOMAIN NOT LIKE '%(GCP)%'))
    AND domain not like '%nih.gov%'
    GROUP BY TIME, SOURCE, DOMAIN
    ORDER BY TIME;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS moving_downloads;

    CREATE TABLE moving_downloads as
    select time, source, avg(downloads)
    over(partition by source
         order by time rows between 29 preceding and current row) as mv30
    from daily_downloads
    order by time, source;
COMMIT;

BEGIN;
    DROP TABLE IF EXISTS to_clouds;


    CREATE TABLE to_clouds AS
    SELECT date_trunc('day',
                    start_ts) AS TIME,
        SOURCE,
        CASE
            WHEN (DOMAIN LIKE '%(GCP)%'
                    OR DOMAIN LIKE '%(AWS Amazon)%') THEN sum(bytecount)
            ELSE 0
        END AS cloudbytes,
        sum(bytecount) AS allbytes
    FROM cloud_sessions
    WHERE (cmds LIKE '%GET%'
        OR cmds LIKE '%HEAD%')
    AND (cmds NOT LIKE '%POST%'
        AND cmds NOT LIKE '%PUT%')
    AND bytecount > 0
    AND (agent NOT LIKE 'aws-cli%'
        AND agent NOT LIKE 'apitools gsutil%')
    GROUP BY TIME,
            SOURCE,
            DOMAIN
    ORDER BY TIME,
            SOURCE;


    DROP TABLE IF EXISTS to_clouds_pct;


    CREATE TABLE to_clouds_pct AS
    SELECT TIME,
        100.0 * sum(cloudbytes) / sum(allbytes) AS percent
    FROM to_clouds
    GROUP BY TIME
    ORDER BY TIME;


    DROP TABLE IF EXISTS to_clouds_users;


    CREATE TABLE to_clouds_users AS
    SELECT date_trunc('day',
                    start_ts) AS TIME,
        count(DISTINCT ip) AS unique_users,
        CASE
            WHEN DOMAIN LIKE '%(GCP)%' THEN count(DISTINCT ip)
            ELSE 0
        END AS gcp_count,
        CASE
            WHEN DOMAIN LIKE '%(AWS Amazon)%' THEN count(DISTINCT ip)
            ELSE 0
        END AS aws_count
    FROM cloud_sessions
    WHERE (cmds LIKE '%GET%'
        OR cmds LIKE '%HEAD%')
    AND (cmds NOT LIKE '%POST%'
        AND cmds NOT LIKE '%PUT%')
    AND bytecount > 0
    AND (agent NOT LIKE 'aws-cli%'
        AND agent NOT LIKE 'apitools gsutil%')
    GROUP BY TIME,
            DOMAIN
    ORDER BY TIME;


    DROP TABLE IF EXISTS to_clouds_users_sum;


    CREATE TABLE to_clouds_users_sum AS
    SELECT TIME,
        sum(unique_users) as total,
        sum(gcp_count) as gcp,
        sum(aws_count) as aws
    FROM to_clouds_users
    GROUP BY TIME
    ORDER BY TIME;
COMMIT;


BEGIN;
    DROP TABLE IF EXISTS toolkit_downloads;
    CREATE TABLE toolkit_downloads AS
    SELECT
        source,
        date_trunc('day', start_ts) AS time,
        count(distinct ip) AS unique_users,
        count(*) AS Downloads,
        sum(bytecount) AS Bytes
    FROM cloud_sessions
    where
    ( cmds like '%GET%' or cmds like '%HEAD%' )
    AND (agent like '%sra-toolkit%' or agent like '%ncbi-vdb%')
    AND domain not like '%nih.gov%'
    group by source, time
    order by time, source;
COMMIT;

ANALYZE;

HERE

date
