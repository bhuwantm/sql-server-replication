#!/bin/bash

# SQL Server Replication Monitoring Script
# This script provides comprehensive monitoring of replication status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SA_PASSWORD="${SA_PASSWORD:-YourStrong!Passw0rd}"
PUBLISHER_CONTAINER="sqlserver-publisher"
SUBSCRIBER_CONTAINER="sqlserver-subscriber"
PUBLISHER_PORT="1440"
SUBSCRIBER_PORT="1434"

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}SQL Server Replication Monitor${NC}"
echo -e "${BLUE}===============================================${NC}"

# Function to execute SQL query and display results
execute_and_display() {
    local container=$1
    local title=$2
    local query=$3
    
    echo -e "\n${YELLOW}$title${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    
    if docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "$query" -C 2>/dev/null; then
        return 0
    else
        echo -e "${RED}✗ Failed to execute query${NC}"
        return 1
    fi
}

# Function to get simple count
get_count() {
    local container=$1
    local query=$2
    docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "$query" -h -1 -W -C 2>/dev/null | tr -d ' \r\n' | tail -1
}

# Check container status
echo -e "\n${BLUE}1. Container Status${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=sqlserver"; then
    echo -e "${GREEN}✓ Containers are running${NC}"
else
    echo -e "${RED}✗ Some containers may not be running${NC}"
fi

# Check database connectivity
echo -e "\n${BLUE}2. Database Connectivity${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

if execute_and_display $PUBLISHER_CONTAINER "Publisher Connection Test" "SELECT @@SERVERNAME as ServerName, GETDATE() as CurrentTime"; then
    echo -e "${GREEN}✓ Publisher is accessible${NC}"
else
    echo -e "${RED}✗ Publisher is not accessible${NC}"
fi

if execute_and_display $SUBSCRIBER_CONTAINER "Subscriber Connection Test" "SELECT @@SERVERNAME as ServerName, GETDATE() as CurrentTime"; then
    echo -e "${GREEN}✓ Subscriber is accessible${NC}"
else
    echo -e "${RED}✗ Subscriber is not accessible${NC}"
fi

# Check SQL Server Agent status
echo -e "\n${BLUE}3. SQL Server Agent Status${NC}"
execute_and_display $PUBLISHER_CONTAINER "Publisher SQL Server Agent Jobs" "
SELECT 
    j.name AS 'Job Name',
    j.enabled AS 'Enabled',
    CASE 
        WHEN ja.run_status = 1 THEN 'Success'
        WHEN ja.run_status = 0 THEN 'Failed'
        WHEN ja.run_status = 2 THEN 'Retry'
        WHEN ja.run_status = 3 THEN 'Canceled'
        WHEN ja.run_status = 4 THEN 'In Progress'
        ELSE 'Unknown'
    END AS 'Last Status'
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
WHERE j.name LIKE '%replication%' OR j.name LIKE '%snapshot%' OR j.name LIKE '%distribution%'
ORDER BY j.name;"

# Check publication status
echo -e "\n${BLUE}4. Publication Status${NC}"
execute_and_display $PUBLISHER_CONTAINER "Publications" "
USE ReplicationDemo;
SELECT 
    name AS 'Publication Name',
    status AS 'Status',
    snapshot_ready AS 'Snapshot Ready',
    allow_push AS 'Allow Push',
    allow_pull AS 'Allow Pull'
FROM syspublications;"

# Check subscription status
echo -e "\n${BLUE}5. Subscription Status${NC}"
execute_and_display $PUBLISHER_CONTAINER "Publisher Side Subscriptions" "
USE ReplicationDemo;
SELECT 
    p.name AS 'Publication',
    s.subscriber_server AS 'Subscriber',
    s.subscriber_db AS 'Subscriber DB',
    s.subscription_type AS 'Type',
    s.status AS 'Status'
FROM syspublications p
LEFT JOIN syssubscriptions s ON p.pubid = s.pubid
ORDER BY p.name;"

execute_and_display $SUBSCRIBER_CONTAINER "Subscriber Side Subscriptions" "
USE ReplicationDemo;
SELECT 
    publisher AS 'Publisher',
    publisher_db AS 'Publisher DB',
    publication AS 'Publication',
    subscription_type AS 'Type',
    status AS 'Status',
    last_updated AS 'Last Updated'
FROM sysmergepullsubscriptions
UNION ALL
SELECT 
    publisher,
    publisher_db,
    publication,
    CASE subscription_type 
        WHEN 0 THEN 'Push'
        WHEN 1 THEN 'Pull'
        WHEN 2 THEN 'Anonymous'
    END,
    status,
    last_updated
FROM syssubscriptions;"

# Check data consistency
echo -e "\n${BLUE}6. Data Consistency Check${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

# Get record counts from both servers
echo -e "${YELLOW}Checking record counts...${NC}"

PUBLISHER_CUSTOMERS=$(get_count $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Customers")
SUBSCRIBER_CUSTOMERS=$(get_count $SUBSCRIBER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Customers")

PUBLISHER_PRODUCTS=$(get_count $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Products")
SUBSCRIBER_PRODUCTS=$(get_count $SUBSCRIBER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Products")

PUBLISHER_ORDERS=$(get_count $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Orders")
SUBSCRIBER_ORDERS=$(get_count $SUBSCRIBER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Orders")

echo -e "\n${YELLOW}Record Count Comparison:${NC}"
echo -e "Table          Publisher    Subscriber   Status"
echo -e "---------------------------------------------"

# Check Customers
if [ "$PUBLISHER_CUSTOMERS" = "$SUBSCRIBER_CUSTOMERS" ]; then
    echo -e "Customers      $PUBLISHER_CUSTOMERS           $SUBSCRIBER_CUSTOMERS          ${GREEN}✓ Synced${NC}"
else
    echo -e "Customers      $PUBLISHER_CUSTOMERS           $SUBSCRIBER_CUSTOMERS          ${RED}✗ Different${NC}"
fi

# Check Products
if [ "$PUBLISHER_PRODUCTS" = "$SUBSCRIBER_PRODUCTS" ]; then
    echo -e "Products       $PUBLISHER_PRODUCTS           $SUBSCRIBER_PRODUCTS          ${GREEN}✓ Synced${NC}"
else
    echo -e "Products       $PUBLISHER_PRODUCTS           $SUBSCRIBER_PRODUCTS          ${RED}✗ Different${NC}"
fi

# Check Orders
if [ "$PUBLISHER_ORDERS" = "$SUBSCRIBER_ORDERS" ]; then
    echo -e "Orders         $PUBLISHER_ORDERS           $SUBSCRIBER_ORDERS          ${GREEN}✓ Synced${NC}"
else
    echo -e "Orders         $PUBLISHER_ORDERS           $SUBSCRIBER_ORDERS          ${RED}✗ Different${NC}"
fi

# Check for replication errors
echo -e "\n${BLUE}7. Recent Replication Errors${NC}"
execute_and_display $PUBLISHER_CONTAINER "Recent Errors (Last 24 hours)" "
SELECT TOP 10
    time AS 'Error Time',
    error_code AS 'Error Code',
    error_text AS 'Error Message'
FROM distribution.dbo.MSrepl_errors
WHERE time > DATEADD(day, -1, GETDATE())
ORDER BY time DESC;"

# Check pending commands
echo -e "\n${BLUE}8. Pending Commands${NC}"
execute_and_display $PUBLISHER_CONTAINER "Undistributed Commands" "
SELECT 
    a.publisher_db AS 'Publisher DB',
    a.article AS 'Article',
    COUNT(*) AS 'Pending Commands'
FROM distribution.dbo.MSrepl_commands rc
INNER JOIN distribution.dbo.MSarticles a ON rc.article_id = a.article_id
GROUP BY a.publisher_db, a.article
HAVING COUNT(*) > 0
ORDER BY COUNT(*) DESC;"

# Performance metrics
echo -e "\n${BLUE}9. Performance Metrics${NC}"
execute_and_display $PUBLISHER_CONTAINER "Distribution Agent Performance" "
SELECT 
    agent_id,
    agent_name,
    start_time,
    time,
    duration,
    comments,
    delivered_transactions,
    delivered_commands,
    average_commands_per_second
FROM distribution.dbo.MSdistribution_history
WHERE time > DATEADD(hour, -2, GETDATE())
ORDER BY time DESC;"

# Summary
echo -e "\n${BLUE}10. Summary${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

TOTAL_ERRORS=$(get_count $PUBLISHER_CONTAINER "SELECT COUNT(*) FROM distribution.dbo.MSrepl_errors WHERE time > DATEADD(day, -1, GETDATE())")
PENDING_COMMANDS=$(get_count $PUBLISHER_CONTAINER "SELECT COUNT(*) FROM distribution.dbo.MSrepl_commands")

echo -e "Recent errors (24h): ${TOTAL_ERRORS:-0}"
echo -e "Pending commands: ${PENDING_COMMANDS:-0}"

if [ "${TOTAL_ERRORS:-0}" -eq 0 ] && [ "${PENDING_COMMANDS:-0}" -eq 0 ]; then
    echo -e "\n${GREEN}✓ Replication appears to be healthy${NC}"
elif [ "${TOTAL_ERRORS:-0}" -gt 0 ]; then
    echo -e "\n${RED}⚠ There are recent replication errors - check error details above${NC}"
elif [ "${PENDING_COMMANDS:-0}" -gt 100 ]; then
    echo -e "\n${YELLOW}⚠ High number of pending commands - replication may be lagging${NC}"
else
    echo -e "\n${YELLOW}⚠ Replication status needs attention${NC}"
fi

echo -e "\n${BLUE}Monitoring complete!${NC}"
echo -e "${YELLOW}Run this script periodically to monitor replication health.${NC}"
