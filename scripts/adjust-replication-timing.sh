#!/bin/bash

# Script to adjust replication timing
# Usage: ./adjust-replication-timing.sh [seconds|minutes|hours] [interval]
# Example: ./adjust-replication-timing.sh seconds 30  (replicate every 30 seconds)
# Example: ./adjust-replication-timing.sh minutes 2   (replicate every 2 minutes)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PUBLISHER_CONTAINER="sqlserver-publisher"
SA_PASSWORD="${SA_PASSWORD:-YourStrong!Passw0rd}"

echo -e "${BLUE}SQL Server Replication Timing Adjustment${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check parameters
if [ $# -ne 2 ]; then
    echo -e "${RED}Usage: $0 [seconds|minutes|hours] [interval]${NC}"
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0 seconds 30    # Replicate every 30 seconds"
    echo -e "  $0 minutes 2     # Replicate every 2 minutes"
    echo -e "  $0 hours 1       # Replicate every 1 hour"
    exit 1
fi

UNIT=$1
INTERVAL=$2

# Validate inputs
if [[ ! "$UNIT" =~ ^(seconds|minutes|hours)$ ]]; then
    echo -e "${RED}Error: Unit must be 'seconds', 'minutes', or 'hours'${NC}"
    exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
    echo -e "${RED}Error: Interval must be a positive integer${NC}"
    exit 1
fi

# Convert to SQL Server frequency parameters
case $UNIT in
    "seconds")
        if [ "$INTERVAL" -lt 10 ]; then
            echo -e "${YELLOW}Warning: Very frequent replication (< 10 seconds) may impact performance${NC}"
        fi
        FREQUENCY_SUBDAY=2  # Seconds
        FREQUENCY_SUBDAY_INTERVAL=$INTERVAL
        ;;
    "minutes")
        FREQUENCY_SUBDAY=4  # Minutes
        FREQUENCY_SUBDAY_INTERVAL=$INTERVAL
        ;;
    "hours")
        FREQUENCY_SUBDAY=8  # Hours
        FREQUENCY_SUBDAY_INTERVAL=$INTERVAL
        ;;
esac

echo -e "${YELLOW}Setting replication frequency to every $INTERVAL $UNIT...${NC}"

# Update the distribution agent schedule
SQL_COMMAND="
USE msdb;
GO

-- Find and update distribution agent jobs
DECLARE @job_name NVARCHAR(256)
DECLARE job_cursor CURSOR FOR
SELECT name FROM sysjobs 
WHERE name LIKE '%ReplicationDemo_Publication%' 
  AND name LIKE '%sqlserver-subscriber%'
  AND category_id = (SELECT category_id FROM syscategories WHERE name = 'REPL-Distribution')

OPEN job_cursor
FETCH NEXT FROM job_cursor INTO @job_name

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Updating job: ' + @job_name
    
    EXEC sp_update_schedule
        @name = @job_name,
        @freq_subday_type = $FREQUENCY_SUBDAY,
        @freq_subday_interval = $FREQUENCY_SUBDAY_INTERVAL
    
    FETCH NEXT FROM job_cursor INTO @job_name
END

CLOSE job_cursor
DEALLOCATE job_cursor

PRINT 'Replication timing updated to every $INTERVAL $UNIT'
"

# Execute the SQL command
if docker exec $PUBLISHER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "$SQL_COMMAND" -C > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Replication timing updated successfully${NC}"
    echo -e "${YELLOW}New setting: Replicate every $INTERVAL $UNIT${NC}"
    
    # Restart the distribution agent to apply changes immediately
    echo -e "${YELLOW}Restarting distribution agent...${NC}"
    
    RESTART_SQL="
    USE msdb;
    DECLARE @job_name NVARCHAR(256)
    DECLARE job_cursor CURSOR FOR
    SELECT name FROM sysjobs 
    WHERE name LIKE '%ReplicationDemo_Publication%' 
      AND name LIKE '%sqlserver-subscriber%'
      AND category_id = (SELECT category_id FROM syscategories WHERE name = 'REPL-Distribution')

    OPEN job_cursor
    FETCH NEXT FROM job_cursor INTO @job_name

    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sp_stop_job @job_name = @job_name
        WAITFOR DELAY '00:00:02'
        EXEC sp_start_job @job_name = @job_name
        PRINT 'Restarted job: ' + @job_name
        FETCH NEXT FROM job_cursor INTO @job_name
    END

    CLOSE job_cursor
    DEALLOCATE job_cursor
    "
    
    if docker exec $PUBLISHER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "$RESTART_SQL" -C > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Distribution agent restarted${NC}"
    else
        echo -e "${YELLOW}⚠ Could not restart distribution agent automatically${NC}"
        echo -e "${YELLOW}  Changes will take effect on next scheduled run${NC}"
    fi
    
else
    echo -e "${RED}✗ Failed to update replication timing${NC}"
    echo -e "${YELLOW}Make sure replication is properly set up first${NC}"
    exit 1
fi

echo -e "${GREEN}Replication timing adjustment completed!${NC}"
