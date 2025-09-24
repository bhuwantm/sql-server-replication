-- Configure SQL Server Subscriber for Transactional Replication
-- This script sets up the subscriber instance for replication

USE master;
GO

-- Enable SQL Server Agent (required for replication)
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

EXEC sp_configure 'Agent XPs', 1;
RECONFIGURE;
GO

-- Ensure the ReplicationDemo database exists on subscriber
-- (it will be created during subscription initialization if it doesn't exist)
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ReplicationDemo')
BEGIN
    CREATE DATABASE ReplicationDemo;
    PRINT 'Database ReplicationDemo created on subscriber';
END
ELSE
BEGIN
    PRINT 'Database ReplicationDemo already exists on subscriber';
END
GO

-- Add the remote distributor
EXEC sp_adddistributor 
    @distributor = N'sqlserver-publisher',
    @password = N'StrongPassword123!';
GO

-- Add subscription to the publication
USE ReplicationDemo;
GO

-- Add pull subscription
EXEC sp_addpullsubscription 
    @publisher = N'sqlserver-publisher',
    @publication = N'ReplicationDemo_Publication',
    @subscriber_db = N'ReplicationDemo',
    @subscription_type = N'pull',
    @sync_type = N'automatic',
    @article = N'all',
    @update_mode = N'read only',
    @subscriber_type = 0;
GO

-- Add pull subscription agent
EXEC sp_addpullsubscription_agent 
    @publisher = N'sqlserver-publisher',
    @publisher_db = N'ReplicationDemo',
    @publication = N'ReplicationDemo_Publication',
    @subscriber = N'sqlserver-subscriber',
    @subscriber_db = N'ReplicationDemo',
    @subscriber_security_mode = 1,
    @distributor = N'sqlserver-publisher',
    @distributor_security_mode = 1,
    @enabled_for_syncmgr = N'False',
    @frequency_type = 64,
    @frequency_interval = 1,
    @frequency_relative_interval = 1,
    @frequency_recurrence_factor = 0,
    @frequency_subday = 4,
    @frequency_subday_interval = 5,
    @active_start_time_of_day = 0,
    @active_end_time_of_day = 235959,
    @active_start_date = 0,
    @active_end_date = 0;
GO

PRINT 'Subscriber configuration completed successfully';
PRINT 'Pull subscription created - replication should start automatically';
GO
