-- Configure SQL Server Publisher for Transactional Replication
-- This script sets up the publisher instance for replication

USE master;
GO

-- Enable SQL Server Agent (required for replication)
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

EXEC sp_configure 'Agent XPs', 1;
RECONFIGURE;
GO

-- Configure the distributor (using the same server as distributor)
EXEC sp_adddistributor 
    @distributor = N'sqlserver-publisher',
    @password = N'StrongPassword123!';
GO

-- Add the distribution database
EXEC sp_adddistributiondb 
    @database = N'distribution',
    @data_folder = N'/var/opt/mssql/data',
    @log_folder = N'/var/opt/mssql/data',
    @log_file_size = 2,
    @min_distretention = 0,
    @max_distretention = 72,
    @history_retention = 48,
    @security_mode = 1;
GO

-- Add the publisher
EXEC sp_adddistpublisher 
    @publisher = N'sqlserver-publisher',
    @distribution_db = N'distribution',
    @security_mode = 1,
    @working_directory = N'/var/opt/mssql/ReplData',
    @trusted = N'false',
    @thirdparty_flag = 0,
    @publisher_type = N'MSSQLSERVER';
GO

-- Enable the database for replication
USE ReplicationDemo;
GO

EXEC sp_replicationdboption 
    @dbname = N'ReplicationDemo',
    @optname = N'publish',
    @value = N'true';
GO

-- Add the publication
EXEC sp_addpublication 
    @publication = N'ReplicationDemo_Publication',
    @description = N'Transactional publication of ReplicationDemo database',
    @sync_method = N'concurrent',
    @retention = 0,
    @allow_push = N'true',
    @allow_pull = N'true',
    @allow_anonymous = N'true',
    @enabled_for_internet = N'false',
    @snapshot_in_defaultfolder = N'true',
    @alt_snapshot_folder = N'',
    @compress_snapshot = N'false',
    @ftp_port = 21,
    @ftp_login = N'anonymous',
    @allow_subscription_copy = N'false',
    @add_to_active_directory = N'false',
    @repl_freq = N'continuous',
    @status = N'active',
    @independent_agent = N'true',
    @immediate_sync = N'true',
    @allow_sync_tran = N'false',
    @autogen_sync_procs = N'false',
    @allow_queued_tran = N'false',
    @allow_dts = N'false',
    @replicate_ddl = 1,
    @allow_initialize_from_backup = N'false',
    @enabled_for_p2p = N'false',
    @enabled_for_het_sub = N'false';
GO

-- Add articles (tables) to the publication
-- Add Customers table
EXEC sp_addarticle 
    @publication = N'ReplicationDemo_Publication',
    @article = N'Customers',
    @source_owner = N'dbo',
    @source_object = N'Customers',
    @type = N'logbased',
    @description = N'Customers table article',
    @creation_script = N'',
    @pre_creation_cmd = N'drop',
    @schema_option = 0x000000000803509F,
    @identityrangemanagementoption = N'manual',
    @destination_table = N'Customers',
    @destination_owner = N'dbo';
GO

-- Add Products table
EXEC sp_addarticle 
    @publication = N'ReplicationDemo_Publication',
    @article = N'Products',
    @source_owner = N'dbo',
    @source_object = N'Products',
    @type = N'logbased',
    @description = N'Products table article',
    @creation_script = N'',
    @pre_creation_cmd = N'drop',
    @schema_option = 0x000000000803509F,
    @identityrangemanagementoption = N'manual',
    @destination_table = N'Products',
    @destination_owner = N'dbo';
GO

-- Add Orders table
EXEC sp_addarticle 
    @publication = N'ReplicationDemo_Publication',
    @article = N'Orders',
    @source_owner = N'dbo',
    @source_object = N'Orders',
    @type = N'logbased',
    @description = N'Orders table article',
    @creation_script = N'',
    @pre_creation_cmd = N'drop',
    @schema_option = 0x000000000803509F,
    @identityrangemanagementoption = N'manual',
    @destination_table = N'Orders',
    @destination_owner = N'dbo';
GO

-- Add OrderDetails table
EXEC sp_addarticle 
    @publication = N'ReplicationDemo_Publication',
    @article = N'OrderDetails',
    @source_owner = N'dbo',
    @source_object = N'OrderDetails',
    @type = N'logbased',
    @description = N'OrderDetails table article',
    @creation_script = N'',
    @pre_creation_cmd = N'drop',
    @schema_option = 0x000000000803509F,
    @identityrangemanagementoption = N'manual',
    @destination_table = N'OrderDetails',
    @destination_owner = N'dbo';
GO

-- Add the snapshot agent
EXEC sp_addpublication_snapshot 
    @publication = N'ReplicationDemo_Publication',
    @frequency_type = 4,
    @frequency_interval = 1,
    @frequency_relative_interval = 1,
    @frequency_recurrence_factor = 0,
    @frequency_subday = 8,
    @frequency_subday_interval = 1,
    @active_start_time_of_day = 0,
    @active_end_time_of_day = 235959,
    @active_start_date = 0,
    @active_end_date = 0,
    @job_login = NULL,
    @job_password = NULL,
    @publisher_security_mode = 1;
GO

-- Start the snapshot agent to create initial snapshot
EXEC sp_startpublication_snapshot @publication = N'ReplicationDemo_Publication';
GO

PRINT 'Publisher configuration completed successfully';
PRINT 'Snapshot agent started - please wait for snapshot generation to complete';
GO
