-- Replication Monitoring and Management Scripts
-- Use these scripts to monitor and manage replication

-- 1. Check replication status
SELECT 
    p.publication AS 'Publication',
    a.article AS 'Article',
    s.status AS 'Status',
    s.subscriber_server AS 'Subscriber',
    s.subscriber_db AS 'Subscriber DB',
    s.subscription_type AS 'Sub Type'
FROM distribution.dbo.MSarticles a
INNER JOIN distribution.dbo.MSpublications p ON a.publication_id = p.publication_id
LEFT JOIN distribution.dbo.MSsubscriptions s ON p.publication_id = s.publication_id
ORDER BY p.publication, a.article;
GO

-- 2. Check replication agents status
SELECT 
    j.name AS 'Job Name',
    j.enabled AS 'Enabled',
    ja.run_status AS 'Last Run Status',
    ja.run_date AS 'Last Run Date',
    ja.run_time AS 'Last Run Time',
    CASE ja.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS 'Status Description'
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
WHERE j.name LIKE '%replication%' OR j.name LIKE '%snapshot%' OR j.name LIKE '%distribution%'
ORDER BY j.name;
GO

-- 3. Check publication details
SELECT 
    name AS 'Publication Name',
    description AS 'Description',
    status AS 'Status',
    snapshot_ready AS 'Snapshot Ready',
    enabled_for_internet AS 'Internet Enabled',
    allow_push AS 'Allow Push',
    allow_pull AS 'Allow Pull'
FROM syspublications;
GO

-- 4. Check articles in publication
SELECT 
    p.name AS 'Publication',
    a.name AS 'Article',
    a.source_owner AS 'Source Owner',
    a.source_object AS 'Source Object',
    a.destination_owner AS 'Dest Owner',
    a.destination_object AS 'Dest Object'
FROM syspublications p
INNER JOIN sysarticles a ON p.pubid = a.pubid
ORDER BY p.name, a.name;
GO

-- 5. Check subscription details
SELECT 
    p.name AS 'Publication',
    s.subscriber_server AS 'Subscriber Server',
    s.subscriber_db AS 'Subscriber Database',
    s.subscription_type AS 'Subscription Type',
    s.status AS 'Status',
    s.sync_type AS 'Sync Type',
    s.update_mode AS 'Update Mode'
FROM syspublications p
INNER JOIN syssubscriptions s ON p.pubid = s.pubid
ORDER BY p.name, s.subscriber_server;
GO

-- 6. Check replication errors
SELECT TOP 20
    time AS 'Error Time',
    error_code AS 'Error Code',
    error_text AS 'Error Message',
    source_type_desc AS 'Source Type'
FROM distribution.dbo.MSrepl_errors
ORDER BY time DESC;
GO

-- 7. Check pending commands (undistributed transactions)
SELECT 
    publisher_db AS 'Publisher DB',
    article AS 'Article',
    COUNT(*) AS 'Pending Commands'
FROM distribution.dbo.MSrepl_commands rc
INNER JOIN distribution.dbo.MSarticles a ON rc.article_id = a.article_id
GROUP BY publisher_db, article
ORDER BY COUNT(*) DESC;
GO

-- 8. Force snapshot generation (if needed)
-- EXEC sp_startpublication_snapshot @publication = N'ReplicationDemo_Publication';

-- 9. Reinitialize subscription (if needed)
-- EXEC sp_reinitsubscription @publication = N'ReplicationDemo_Publication', @article = N'all';

PRINT 'Replication monitoring queries completed';
GO
