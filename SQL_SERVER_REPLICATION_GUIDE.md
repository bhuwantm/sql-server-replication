# SQL Server Transactional Replication - Comprehensive Guide

## Table of Contents
- [Overview](#overview)
- [Replication Components and Agents](#replication-components-and-agents)
- [Replication Process Flow](#replication-process-flow)
- [Project Setup Details](#project-setup-details)
- [Configuration Parameters](#configuration-parameters)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)

## Overview

This project implements **SQL Server Transactional Replication** using Docker containers to demonstrate real-time data synchronization between a Publisher and Subscriber database. Transactional replication is ideal for scenarios requiring near real-time data distribution with high consistency.

### Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Publisher     │───▶│   Distributor   │───▶│   Subscriber    │
│ sqlserver-      │    │ (Same as        │    │ sqlserver-      │
│ publisher:1440  │    │  Publisher)     │    │ subscriber:1434 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Replication Components and Agents

### 1. Distributor
The **Distributor** is the central component that manages replication data flow and stores replication metadata.

**Key Functions:**
- Stores the **Distribution Database** containing replication commands
- Manages replication agent jobs
- Tracks subscription information
- Maintains replication history and performance metrics

**Configuration in Project:**
```sql
-- Distributor setup
EXEC sp_adddistributor 
    @distributor = N'sqlserver-publisher',
    @password = N'StrongPassword123!';

-- Distribution database creation
EXEC sp_adddistributiondb 
    @database = N'distribution',
    @data_folder = N'/var/opt/mssql/data',
    @log_folder = N'/var/opt/mssql/data',
    @min_distretention = 0,      -- Minimum retention (hours)
    @max_distretention = 72,     -- Maximum retention (hours)
    @history_retention = 48;     -- History retention (hours)
```

### 2. Publication
A **Publication** is a collection of articles (tables, views, or stored procedures) that are replicated as a unit.

**Configuration:**
```sql
EXEC sp_addpublication 
    @publication = N'ReplicationDemo_Publication',
    @repl_freq = N'continuous',           -- Continuous replication
    @immediate_sync = N'true',            -- New subscriptions get immediate sync
    @allow_push = N'true',               -- Allow push subscriptions
    @allow_pull = N'true',               -- Allow pull subscriptions
    @replicate_ddl = 1;                  -- Replicate DDL changes
```

### 3. Replication Agents

#### A. Log Reader Agent
**Purpose:** Reads the transaction log of published databases and copies marked transactions to the distribution database.

**Key Characteristics:**
- Runs continuously on the publisher
- One Log Reader Agent per published database
- Critical for transactional replication performance

**Job Creation:**
```sql
-- Automatically created when publication is added
-- Job name format: PUBLISHER-DatabaseName-LogReaderAgentId
```

**Monitoring:**
```sql
-- Check Log Reader Agent status
SELECT name, enabled FROM msdb.dbo.sysjobs 
WHERE name LIKE '%ReplicationDemo%' AND name NOT LIKE '%Distribution%';
```

#### B. Snapshot Agent
**Purpose:** Creates initial snapshot files containing schema and data for published articles.

**Key Functions:**
- Generates schema scripts (.sch files)
- Creates bulk copy data files (.bcp files)
- Runs on-demand or scheduled basis
- Required for initial synchronization

**Configuration:**
```sql
EXEC sp_addpublication_snapshot 
    @publication = N'ReplicationDemo_Publication',
    @frequency_type = 4,              -- Daily
    @frequency_subday = 2,            -- Seconds
    @frequency_subday_interval = 30;  -- Every 30 seconds
```

**Snapshot Process:**
1. Locks published tables (briefly)
2. Generates schema scripts for each article
3. Bulk copies data from each table
4. Creates snapshot metadata
5. Posts commands to distribution database

#### C. Distribution Agent
**Purpose:** Moves transactions and snapshot files from the distribution database to subscribers.

**Key Characteristics:**
- One agent per push subscription
- Runs continuously or on schedule
- Handles initial synchronization and ongoing changes

**Configuration in Project:**
```sql
EXEC sp_addpushsubscription_agent 
    @publication = N'ReplicationDemo_Publication',
    @subscriber = N'sqlserver-subscriber',
    @subscriber_db = N'ReplicationDemo',
    @frequency_subday = 2,            -- Frequency unit (seconds)
    @frequency_subday_interval = 10;  -- Every 10 seconds
```

**Agent Process Flow:**
1. Connects to distributor database
2. Reads pending commands for subscription
3. Connects to subscriber database
4. Applies schema changes first
5. Applies data changes in transaction order
6. Updates distribution history
7. Commits changes and updates sync status

## Replication Process Flow

### Initial Setup Phase

#### 1. Database Preparation
```sql
-- Enable database for replication
EXEC sp_replicationdboption 
    @dbname = N'ReplicationDemo',
    @optname = N'publish',
    @value = N'true';
```

This command:
- Adds replication system tables to the database
- Enables transaction log marking for replication
- Creates necessary metadata structures

#### 2. Article Addition
For each table to be replicated:
```sql
EXEC sp_addarticle 
    @publication = N'ReplicationDemo_Publication',
    @article = N'Customers',
    @source_object = N'Customers',
    @type = N'logbased',                    -- Transaction log-based
    @pre_creation_cmd = N'drop',            -- Drop table if exists on subscriber
    @schema_option = 0x000000000803509F,    -- Schema options bitmask
    @identityrangemanagementoption = N'manual';
```

**Schema Options Explained:**
- `0x000000000803509F` includes:
  - Primary keys
  - Indexes
  - Check constraints
  - Foreign key constraints
  - Column defaults
  - User-defined data types

#### 3. Subscription Creation
```sql
-- Add subscriber server
EXEC sp_addsubscriber 
    @subscriber = N'sqlserver-subscriber',
    @security_mode = 0,  -- SQL Server authentication
    @login = N'sa',
    @password = N'YourStrong!Passw0rd';

-- Create push subscription
EXEC sp_addsubscription 
    @publication = N'ReplicationDemo_Publication',
    @subscriber = N'sqlserver-subscriber',
    @destination_db = N'ReplicationDemo',
    @subscription_type = N'push',
    @sync_type = N'automatic';  -- Use snapshot for initial sync
```

### Ongoing Replication Process

#### 1. Transaction Capture
When data changes occur on the publisher:

1. **Transaction Logging:** All DML operations (INSERT, UPDATE, DELETE) are logged in the transaction log with replication markers
2. **Log Reader Scanning:** The Log Reader Agent continuously scans the transaction log for marked transactions
3. **Command Generation:** Marked transactions are converted into replication commands and stored in the distribution database

**Example Transaction Flow:**
```sql
-- Original transaction on publisher
INSERT INTO Customers (FirstName, LastName, Email) 
VALUES ('John', 'Doe', 'john@example.com');

-- Converted to replication command in distribution database
-- Stored as: sp_MSins_dboCustomers @c1='John', @c2='Doe', @c3='john@example.com'
```

#### 2. Command Distribution
The Distribution Agent process:

1. **Command Retrieval:** Queries the distribution database for pending commands
2. **Subscriber Connection:** Establishes connection to subscriber database
3. **Command Application:** Executes replication commands in original transaction order
4. **Batch Processing:** Groups commands into batches for efficiency
5. **Error Handling:** Manages conflicts and errors according to configuration

#### 3. Synchronization Verification
```sql
-- Check pending commands
SELECT COUNT(*) as PendingCommands 
FROM distribution.dbo.MSrepl_commands 
WHERE publisher_database_id = (
    SELECT publisher_database_id 
    FROM distribution.dbo.MSpublications 
    WHERE publication = 'ReplicationDemo_Publication'
);
```

## Project Setup Details

### Container Architecture

#### Publisher Container (`sqlserver-publisher`)
```yaml
services:
  sqlserver-publisher:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: sqlserver-publisher
    hostname: sqlserver-publisher  # Important for replication networking
    environment:
      - MSSQL_AGENT_ENABLED=true   # Required for replication agents
    ports:
      - "1440:1433"
    volumes:
      - publisher_data:/var/opt/mssql
      - ./sql/publisher:/opt/sql/publisher
    healthcheck:
      test: ["/opt/mssql-tools18/bin/sqlcmd", "-S", "localhost", 
             "-U", "sa", "-P", "${SA_PASSWORD}", "-Q", "SELECT 1", "-C"]
```

**Key Configuration Points:**
- **SQL Server Agent Enabled:** Essential for running replication agent jobs
- **Hostname:** Used by replication for inter-server communication
- **Health Check:** Uses `mssql-tools18` (SQL Server 2022 compatibility)
- **Volume Mounts:** Separate volumes for persistent data and SQL scripts

#### Subscriber Container (`sqlserver-subscriber`)
```yaml
  sqlserver-subscriber:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: sqlserver-subscriber 
    hostname: sqlserver-subscriber
    depends_on:
      sqlserver-publisher:
        condition: service_healthy  # Wait for publisher readiness
```

### Network Configuration
```yaml
networks:
  replication-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16  # Dedicated subnet for replication traffic
```

### Detailed Setup Process

#### Phase 1: Infrastructure Setup
1. **Container Creation:** Docker Compose creates SQL Server instances
2. **Health Checks:** Ensures both instances are operational
3. **Network Setup:** Establishes inter-container communication
4. **Volume Mounting:** Persistent storage and script access

#### Phase 2: Database Initialization
Located in `sql/shared/01-create-database.sql`:
```sql
-- Create database with appropriate settings
CREATE DATABASE ReplicationDemo
ON (NAME = 'ReplicationDemo_Data',
    FILENAME = '/var/opt/mssql/data/ReplicationDemo.mdf',
    SIZE = 100MB,
    MAXSIZE = 1GB,
    FILEGROWTH = 10MB)
LOG ON (NAME = 'ReplicationDemo_Log',
        FILENAME = '/var/opt/mssql/data/ReplicationDemo_Log.ldf',
        SIZE = 10MB,
        MAXSIZE = 100MB,
        FILEGROWTH = 10%);

-- Set recovery model to FULL (required for transactional replication)
ALTER DATABASE ReplicationDemo SET RECOVERY FULL;

-- Create tables with proper indexing for replication performance
CREATE TABLE Customers (
    CustomerID int IDENTITY(1,1) PRIMARY KEY,  -- Primary key required
    FirstName nvarchar(50) NOT NULL,
    LastName nvarchar(50) NOT NULL,
    Email nvarchar(100) UNIQUE NOT NULL,       -- Unique constraints help with conflicts
    Phone nvarchar(20),
    Address nvarchar(200),
    CreatedDate datetime2 DEFAULT GETDATE()
);
```

#### Phase 3: Publisher Configuration
Located in `sql/publisher/02-setup-publisher.sql`:

1. **Enable Advanced Options:**
```sql
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Agent XPs', 1;  -- Enable SQL Server Agent extended procedures
RECONFIGURE;
```

2. **Distributor Setup:**
```sql
-- Working directory creation (fixed in troubleshooting)
-- Directory: /var/opt/mssql/ReplData
EXEC sp_adddistributor 
    @distributor = N'sqlserver-publisher',
    @password = N'StrongPassword123!';
```

3. **Distribution Database:**
```sql
EXEC sp_adddistributiondb 
    @database = N'distribution',
    @data_folder = N'/var/opt/mssql/data',
    @log_folder = N'/var/opt/mssql/data',
    @log_file_size = 2,              -- Initial size in MB
    @min_distretention = 0,          -- Minimum retention period
    @max_distretention = 72,         -- Maximum retention (72 hours)
    @history_retention = 48,         -- Agent history retention
    @security_mode = 1;              -- Windows authentication (container context)
```

4. **Publisher Registration:**
```sql
EXEC sp_adddistpublisher 
    @publisher = N'sqlserver-publisher',
    @distribution_db = N'distribution',
    @security_mode = 1,
    @working_directory = N'/var/opt/mssql/ReplData',  -- Snapshot storage location
    @trusted = N'false',
    @publisher_type = N'MSSQLSERVER';
```

#### Phase 4: Publication and Article Setup

1. **Database Enablement:**
```sql
USE ReplicationDemo;
EXEC sp_replicationdboption 
    @dbname = N'ReplicationDemo',
    @optname = N'publish',
    @value = N'true';
```

2. **Publication Creation:**
```sql
EXEC sp_addpublication 
    @publication = N'ReplicationDemo_Publication',
    @description = N'Transactional publication of ReplicationDemo database',
    @sync_method = N'concurrent',        -- Allow concurrent access during snapshot
    @retention = 0,                      -- Infinite retention
    @repl_freq = N'continuous',          -- Continuous replication
    @status = N'active',                 -- Immediately active
    @immediate_sync = N'true',           -- New subscriptions sync immediately
    @replicate_ddl = 1;                  -- Replicate DDL changes
```

3. **Article Addition (Per Table):**
```sql
EXEC sp_addarticle 
    @publication = N'ReplicationDemo_Publication',
    @article = N'Customers',
    @source_owner = N'dbo',
    @source_object = N'Customers',
    @type = N'logbased',                 -- Transaction log-based replication
    @description = N'Customers table article',
    @pre_creation_cmd = N'drop',         -- Drop/recreate on subscriber
    @schema_option = 0x000000000803509F, -- Full schema replication
    @identityrangemanagementoption = N'manual',
    @destination_table = N'Customers',
    @destination_owner = N'dbo';
```

#### Phase 5: Subscription Configuration
Located in `sql/publisher/04-setup-push-subscription.sql`:

1. **Subscriber Registration:**
```sql
EXEC sp_addsubscriber 
    @subscriber = N'sqlserver-subscriber',  -- Hostname must match container name
    @type = 0,                              -- SQL Server subscriber
    @login = N'sa',                         -- Subscriber login
    @password = N'YourStrong!Passw0rd',    -- Subscriber password
    @description = N'Subscriber server for ReplicationDemo',
    @security_mode = 0;                     -- SQL Server authentication
```

2. **Push Subscription Creation:**
```sql
EXEC sp_addsubscription 
    @publication = N'ReplicationDemo_Publication',
    @subscriber = N'sqlserver-subscriber',
    @destination_db = N'ReplicationDemo',
    @subscription_type = N'push',           -- Publisher pushes changes
    @sync_type = N'automatic',              -- Use snapshot for initial sync
    @article = N'all',                      -- Include all articles
    @update_mode = N'read only',            -- Subscriber is read-only
    @subscriber_type = 0;                   -- Regular subscriber
```

3. **Distribution Agent Configuration:**
```sql
EXEC sp_addpushsubscription_agent 
    @publication = N'ReplicationDemo_Publication',
    @subscriber = N'sqlserver-subscriber',
    @subscriber_db = N'ReplicationDemo',
    @subscriber_security_mode = 0,          -- SQL authentication to subscriber
    @subscriber_login = N'sa',
    @subscriber_password = N'YourStrong!Passw0rd',
    @frequency_type = 64,                   -- Continuous
    @frequency_subday = 2,                  -- Frequency unit: seconds
    @frequency_subday_interval = 10,        -- Every 10 seconds
    @active_start_time_of_day = 0,          -- Start time: midnight
    @active_end_time_of_day = 235959;       -- End time: 11:59:59 PM
```

#### Phase 6: Initial Synchronization

1. **Snapshot Agent Creation:**
```sql
EXEC sp_addpublication_snapshot 
    @publication = N'ReplicationDemo_Publication',
    @frequency_type = 4,                    -- Daily
    @frequency_subday = 2,                  -- Seconds
    @frequency_subday_interval = 30,        -- Every 30 seconds
    @publisher_security_mode = 1;           -- Integrated security
```

2. **Snapshot Generation:**
```sql
EXEC sp_startpublication_snapshot 
    @publication = N'ReplicationDemo_Publication';
```

The snapshot process:
- Locks published tables briefly
- Generates schema scripts (.sch files)
- Creates bulk copy data files (.bcp files)
- Posts initialization commands to distribution database
- Unlocks tables

## Configuration Parameters

### Timing Configuration
```sql
-- Distribution Agent Frequency Parameters
@frequency_type = 64          -- Continuous operation
@frequency_subday = 2         -- Unit: 1=Once, 2=Seconds, 4=Minutes, 8=Hours
@frequency_subday_interval    -- Interval based on frequency_subday unit
```

**Common Timing Configurations:**
- **High Frequency (5 seconds):** `@frequency_subday=2, @frequency_subday_interval=5`
- **Standard (2 minutes):** `@frequency_subday=4, @frequency_subday_interval=2`
- **Low Frequency (1 hour):** `@frequency_subday=8, @frequency_subday_interval=1`

### Schema Options Bitmask
The `@schema_option` parameter controls what schema elements are replicated:
```
0x000000000803509F breaks down to:
- 0x00000001: Primary key constraints
- 0x00000002: Check constraints  
- 0x00000008: Clustered indexes
- 0x00000010: Nonclustered indexes
- 0x00000020: Foreign key constraints
- 0x00000080: Column defaults
- 0x00002000: User-defined data types
- 0x00008000: Identity property
- 0x00800000: Extended properties
```

### Retention Settings
```sql
-- Distribution database retention
@min_distretention = 0        -- Minimum hours to keep commands
@max_distretention = 72       -- Maximum hours to keep commands
@history_retention = 48       -- Hours to keep agent history
```

## Troubleshooting

### Common Issues and Solutions

#### 1. "sqlcmd: command not found" Error
**Problem:** Wrong path to sqlcmd in SQL Server 2022 containers
**Solution:** Use `/opt/mssql-tools18/bin/sqlcmd` instead of `/opt/mssql-tools/bin/sqlcmd`

#### 2. "Cannot connect to Subscriber" Error
**Problem:** Hostname case sensitivity or network connectivity
**Solution:** 
- Ensure subscriber hostname matches exactly: `sqlserver-subscriber`
- Verify containers are on same network
- Check firewall settings

#### 3. "Invalid working directory" Error
**Problem:** Replication working directory doesn't exist
**Solution:**
```bash
docker exec --user root sqlserver-publisher mkdir -p /var/opt/mssql/ReplData
docker exec --user root sqlserver-publisher chown mssql:root /var/opt/mssql/ReplData
```

#### 4. Replication Lag Issues
**Problem:** Changes take too long to replicate
**Investigation:**
```sql
-- Check pending commands
SELECT COUNT(*) FROM distribution.dbo.MSrepl_commands;

-- Check agent job status
SELECT name, enabled, last_run_outcome 
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
WHERE name LIKE '%ReplicationDemo%';
```

### Monitoring Queries

#### Distribution Agent Status
```sql
USE msdb;
SELECT 
    j.name as JobName,
    j.enabled,
    js.last_run_date,
    js.last_run_time,
    CASE js.last_run_outcome 
        WHEN 1 THEN 'Success'
        WHEN 0 THEN 'Failed'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        ELSE 'Unknown'
    END as LastOutcome
FROM sysjobs j 
LEFT JOIN sysjobservers js ON j.job_id = js.job_id
WHERE j.name LIKE '%ReplicationDemo%';
```

#### Replication Latency
```sql
USE distribution;
SELECT 
    p.publication,
    COUNT(c.command_id) as PendingCommands,
    MAX(c.entry_time) as OldestCommand
FROM MSpublications p
LEFT JOIN MSrepl_commands c ON p.publication_id = c.publication_id
WHERE p.publication = 'ReplicationDemo_Publication'
GROUP BY p.publication;
```

#### Subscription Status
```sql
USE ReplicationDemo;
-- Check if database is properly configured for replication
SELECT 
    name,
    is_published,
    is_subscribed,
    is_merge_published,
    is_distributor
FROM sys.databases 
WHERE name = 'ReplicationDemo';
```

## Performance Tuning

### Optimization Strategies

#### 1. Index Optimization
Ensure proper indexing on replicated tables:
```sql
-- Primary keys are required for replication
-- Additional indexes for frequently filtered columns
CREATE INDEX IX_Customers_Email ON Customers(Email);
CREATE INDEX IX_Orders_CustomerID ON Orders(CustomerID);
```

#### 2. Batch Size Tuning
```sql
-- Modify distribution agent profile
-- -CommitBatchSize: Number of transactions per commit (default: 100)
-- -CommitBatchThreshold: Max transactions before forced commit (default: 1000)
```

#### 3. Network Optimization
- Use dedicated network for replication traffic
- Consider compression for high-latency networks
- Monitor network bandwidth utilization

#### 4. Resource Allocation
```yaml
# Docker Compose resource limits
services:
  sqlserver-publisher:
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2.0'
        reservations:
          memory: 2G
          cpus: '1.0'
```

### Performance Monitoring

#### Agent Performance Metrics
```sql
-- Distribution agent performance
USE distribution;
SELECT 
    runstatus,
    time,
    comments,
    delivered_transactions,
    delivered_commands,
    average_commands_per_second
FROM MSdistribution_history 
WHERE agent_id = (SELECT agent_id FROM MSdistribution_agents 
                  WHERE name LIKE '%ReplicationDemo%')
ORDER BY time DESC;
```

#### System Resource Usage
```sql
-- Check SQL Server performance counters
SELECT 
    object_name,
    counter_name,
    cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Replication%'
   OR (object_name LIKE '%SQL Statistics%' AND counter_name = 'Batch Requests/sec');
```

---

## Scripts Reference

### Available Management Scripts

#### `scripts/setup-replication.sh`
- Complete automated setup of replication
- Handles container startup and health checks
- Executes all SQL setup scripts in correct order

#### `scripts/monitor-replication.sh`
- Real-time replication status monitoring
- Agent job status and performance metrics
- Data consistency verification

#### `scripts/adjust-replication-timing.sh`
- Dynamic replication frequency adjustment
- Supports seconds, minutes, hours intervals
- Automatically restarts agents with new settings

#### `scripts/diagnosis.sh`
- Comprehensive health check and troubleshooting
- Container connectivity testing
- Manual connection verification

#### `scripts/cleanup.sh`
- Complete replication cleanup and reset
- Removes publications, subscriptions, and test data
- Prepares environment for fresh setup

---

*This comprehensive guide covers all aspects of SQL Server Transactional Replication implementation in the project. For additional support, refer to the monitoring scripts and troubleshooting sections.*
