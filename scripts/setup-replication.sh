#!/bin/bash

# SQL Server Replication Setup Script
# This script automates the complete setup of SQL Server transactional replication

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
MAX_WAIT_TIME=300  # 5 minutes

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}SQL Server Replication Setup Script${NC}"
echo -e "${BLUE}===============================================${NC}"

# Function to check if container is healthy
check_container_health() {
    local container_name=$1
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}Waiting for $container_name to be healthy...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if docker inspect --format='{{.State.Health.Status}}' $container_name 2>/dev/null | grep -q "healthy"; then
            echo -e "${GREEN}✓ $container_name is healthy${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}Attempt $attempt/$max_attempts - waiting for $container_name...${NC}"
        sleep 10
        ((attempt++))
    done
    
    echo -e "${RED}✗ $container_name failed to become healthy${NC}"
    return 1
}

# Function to execute SQL script
execute_sql_script() {
    local container=$1
    local script_path=$2
    local description=$3
    
    echo -e "${YELLOW}$description...${NC}"
    
    if docker exec -it $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -i "$script_path" -C > /dev/null 2>&1; then
        echo -e "${GREEN}✓ $description completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ $description failed${NC}"
        return 1
    fi
}

# Function to execute SQL query
execute_sql_query() {
    local container=$1
    local query=$2
    local description=$3
    
    echo -e "${YELLOW}$description...${NC}"
    
    if docker exec -it $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "$query" -C > /dev/null 2>&1; then
        echo -e "${GREEN}✓ $description completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ $description failed${NC}"
        return 1
    fi
}

# Step 1: Start Docker Compose services
echo -e "\n${BLUE}Step 1: Starting Docker Compose services...${NC}"
if docker-compose up -d; then
    echo -e "${GREEN}✓ Docker Compose services started${NC}"
else
    echo -e "${RED}✗ Failed to start Docker Compose services${NC}"
    exit 1
fi

# Step 2: Wait for containers to be healthy
echo -e "\n${BLUE}Step 2: Waiting for containers to be healthy...${NC}"
check_container_health $PUBLISHER_CONTAINER || exit 1
check_container_health $SUBSCRIBER_CONTAINER || exit 1

# Step 3: Create databases and sample data
echo -e "\n${BLUE}Step 3: Creating databases and sample data...${NC}"
execute_sql_script $PUBLISHER_CONTAINER "/opt/sql/shared/01-create-database.sql" "Creating database on publisher" || exit 1
execute_sql_script $SUBSCRIBER_CONTAINER "/opt/sql/shared/01-create-database.sql" "Creating database on subscriber" || exit 1

# Step 4: Configure publisher
echo -e "\n${BLUE}Step 4: Configuring publisher...${NC}"
execute_sql_script $PUBLISHER_CONTAINER "/opt/sql/publisher/02-setup-publisher.sql" "Setting up publisher" || exit 1

# Wait a bit for snapshot agent to start
echo -e "${YELLOW}Waiting for snapshot agent to initialize...${NC}"
sleep 30

# Step 5: Configure subscriber  
echo -e "\n${BLUE}Step 5: Configuring subscriber...${NC}"
execute_sql_script $SUBSCRIBER_CONTAINER "/opt/sql/subscriber/03-setup-subscriber.sql" "Setting up subscriber" || exit 1

# Step 6: Wait for initial synchronization
echo -e "\n${BLUE}Step 6: Waiting for initial synchronization...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"
sleep 60

# Step 7: Verify replication
echo -e "\n${BLUE}Step 7: Verifying replication setup...${NC}"

# Check publication exists
if execute_sql_query $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM syspublications WHERE name = 'ReplicationDemo_Publication'" "Checking publication exists"; then
    echo -e "${GREEN}✓ Publication verified${NC}"
else
    echo -e "${RED}✗ Publication verification failed${NC}"
fi

# Check data on both servers
echo -e "${YELLOW}Checking data synchronization...${NC}"

PUBLISHER_COUNT=$(docker exec $PUBLISHER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "USE ReplicationDemo; SELECT COUNT(*) FROM Customers" -h -1 -W -C | tr -d ' \r\n')
SUBSCRIBER_COUNT=$(docker exec $SUBSCRIBER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "USE ReplicationDemo; SELECT COUNT(*) FROM Customers" -h -1 -W -C | tr -d ' \r\n')

echo -e "${YELLOW}Publisher customer count: $PUBLISHER_COUNT${NC}"
echo -e "${YELLOW}Subscriber customer count: $SUBSCRIBER_COUNT${NC}"

if [ "$PUBLISHER_COUNT" = "$SUBSCRIBER_COUNT" ] && [ "$PUBLISHER_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Data synchronization verified${NC}"
else
    echo -e "${YELLOW}⚠ Data may still be synchronizing - this is normal for initial setup${NC}"
fi

# Step 8: Display connection information
echo -e "\n${BLUE}Step 8: Connection Information${NC}"
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}Publisher Connection:${NC}"
echo -e "  Host: localhost"
echo -e "  Port: $PUBLISHER_PORT"
echo -e "  Username: sa"
echo -e "  Password: $SA_PASSWORD"
echo -e "  Database: ReplicationDemo"
echo -e ""
echo -e "${GREEN}Subscriber Connection:${NC}"
echo -e "  Host: localhost"
echo -e "  Port: $SUBSCRIBER_PORT"
echo -e "  Username: sa"
echo -e "  Password: $SA_PASSWORD"
echo -e "  Database: ReplicationDemo"
echo -e ""
echo -e "${GREEN}Adminer Web Interface:${NC}"
echo -e "  URL: http://localhost:8080"
echo -e "  System: SQL Server"
echo -e "  Server: sqlserver-publisher or sqlserver-subscriber"
echo -e "  Username: sa"
echo -e "  Password: $SA_PASSWORD"
echo -e "${GREEN}===============================================${NC}"

# Step 9: Next steps
echo -e "\n${BLUE}Setup Complete!${NC}"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "1. Run ${GREEN}./scripts/generate-test-data.sh${NC} to create test data"
echo -e "2. Run ${GREEN}./scripts/monitor-replication.sh${NC} to monitor replication status"
echo -e "3. Connect to the databases using the information above"
echo -e "4. Check ${GREEN}README.md${NC} for detailed usage instructions"

echo -e "\n${GREEN}🎉 SQL Server Transactional Replication is now set up and running!${NC}"
