#!/bin/bash

# SQL Server Replication Cleanup Script
# This script provides options to clean up the replication environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}SQL Server Replication Cleanup Script${NC}"
echo -e "${BLUE}===============================================${NC}"

# Function to prompt for confirmation
confirm() {
    local message=$1
    local default=${2:-"n"}
    
    if [ "$default" = "y" ]; then
        local prompt="[Y/n]"
    else
        local prompt="[y/N]"
    fi
    
    echo -e "${YELLOW}$message $prompt${NC}"
    read -r response
    
    if [ "$default" = "y" ]; then
        case "$response" in
            [nN][oO]|[nN]) return 1 ;;
            *) return 0 ;;
        esac
    else
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# Show current status
echo -e "\n${BLUE}Current Environment Status:${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

echo -e "\n${YELLOW}Running containers:${NC}"
docker ps --filter "name=sqlserver" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No containers found"

echo -e "\n${YELLOW}Docker volumes:${NC}"
docker volume ls --filter "name=sqlserver-replication" || echo "No volumes found"

echo -e "\n${YELLOW}Docker networks:${NC}"
docker network ls --filter "name=sqlserver-replication" || echo "No networks found"

# Cleanup options
echo -e "\n${BLUE}Cleanup Options:${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

# Option 1: Stop containers only
if confirm "1. Stop containers (keep data and configuration)?"; then
    echo -e "\n${YELLOW}Stopping containers...${NC}"
    if docker-compose stop; then
        echo -e "${GREEN}✓ Containers stopped successfully${NC}"
    else
        echo -e "${RED}✗ Failed to stop containers${NC}"
    fi
fi

# Option 2: Remove containers but keep volumes
if confirm "2. Remove containers but keep data volumes?"; then
    echo -e "\n${YELLOW}Removing containers (keeping volumes)...${NC}"
    if docker-compose down; then
        echo -e "${GREEN}✓ Containers removed successfully${NC}"
        echo -e "${GREEN}✓ Data volumes preserved${NC}"
    else
        echo -e "${RED}✗ Failed to remove containers${NC}"
    fi
fi

# Option 3: Complete cleanup (WARNING)
echo -e "\n${RED}⚠ WARNING: The following option will delete ALL data!${NC}"
if confirm "3. COMPLETE CLEANUP - Remove everything including data volumes? (THIS WILL DELETE ALL DATA)"; then
    echo -e "\n${RED}⚠ FINAL WARNING: This will permanently delete all SQL Server data!${NC}"
    if confirm "Are you absolutely sure you want to delete all data?"; then
        echo -e "\n${YELLOW}Performing complete cleanup...${NC}"
        
        # Stop and remove containers, volumes, and networks
        if docker-compose down -v --remove-orphans; then
            echo -e "${GREEN}✓ Containers, volumes, and networks removed${NC}"
        else
            echo -e "${RED}✗ Failed to remove some components${NC}"
        fi
        
        # Remove any orphaned volumes
        echo -e "\n${YELLOW}Cleaning up any orphaned volumes...${NC}"
        ORPHANED_VOLUMES=$(docker volume ls -q --filter "dangling=true" | grep -E "(publisher_data|subscriber_data)" || true)
        if [ -n "$ORPHANED_VOLUMES" ]; then
            echo "$ORPHANED_VOLUMES" | xargs docker volume rm
            echo -e "${GREEN}✓ Orphaned volumes cleaned up${NC}"
        else
            echo -e "${GREEN}✓ No orphaned volumes found${NC}"
        fi
        
        # Clean up Docker system (optional)
        if confirm "4. Also run Docker system cleanup (remove unused images, containers, networks)?"; then
            echo -e "\n${YELLOW}Running Docker system cleanup...${NC}"
            docker system prune -f
            echo -e "${GREEN}✓ Docker system cleanup completed${NC}"
        fi
        
        echo -e "\n${GREEN}✓ Complete cleanup finished${NC}"
        echo -e "${YELLOW}You can now run './scripts/setup-replication.sh' to start fresh${NC}"
    else
        echo -e "${YELLOW}Complete cleanup cancelled${NC}"
    fi
fi

# Option 4: Reset replication only (keep containers running)
if confirm "4. Reset replication configuration only (keep containers and base data)?"; then
    SA_PASSWORD="${SA_PASSWORD:-YourStrong!Passw0rd}"
    PUBLISHER_CONTAINER="sqlserver-publisher"
    SUBSCRIBER_CONTAINER="sqlserver-subscriber"
    PUBLISHER_PORT="1440"
    SUBSCRIBER_PORT="1434"
    
    echo -e "\n${YELLOW}Resetting replication configuration...${NC}"
    
    # Drop publication on publisher
    echo -e "${YELLOW}Removing publication...${NC}"
    docker exec $PUBLISHER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "
    USE ReplicationDemo;
    IF EXISTS (SELECT * FROM syspublications WHERE name = 'ReplicationDemo_Publication')
    BEGIN
        EXEC sp_droppublication @publication = N'ReplicationDemo_Publication';
        PRINT 'Publication dropped';
    END
    " 2>/dev/null || echo -e "${YELLOW}Publication may not exist${NC}"
    
    # Drop subscription on subscriber
    echo -e "${YELLOW}Removing subscription...${NC}"
    docker exec $SUBSCRIBER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "
    USE ReplicationDemo;
    IF EXISTS (SELECT * FROM syspullsubscriptions WHERE publication = 'ReplicationDemo_Publication')
    BEGIN
        EXEC sp_droppullsubscription 
            @publisher = N'sqlserver-publisher',
            @publisher_db = N'ReplicationDemo',
            @publication = N'ReplicationDemo_Publication';
        PRINT 'Subscription dropped';
    END
    " 2>/dev/null || echo -e "${YELLOW}Subscription may not exist${NC}"
    
    # Disable database for replication
    echo -e "${YELLOW}Disabling database for replication...${NC}"
    docker exec $PUBLISHER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "
    USE ReplicationDemo;
    EXEC sp_replicationdboption 
        @dbname = N'ReplicationDemo',
        @optname = N'publish',
        @value = N'false';
    " 2>/dev/null || echo -e "${YELLOW}Database replication settings reset${NC}"
    
    echo -e "${GREEN}✓ Replication configuration reset${NC}"
    echo -e "${YELLOW}You can now run the publisher and subscriber setup scripts again${NC}"
fi

# Option 5: Clean test data only
if confirm "5. Remove test data only (keep replication configuration)?"; then
    SA_PASSWORD="${SA_PASSWORD:-YourStrong!Passw0rd}"
    PUBLISHER_CONTAINER="sqlserver-publisher"
    
    echo -e "\n${YELLOW}Removing test data...${NC}"
    
    # Delete test data
    docker exec $PUBLISHER_CONTAINER /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "
    USE ReplicationDemo;
    
    -- Delete test order details first (foreign key constraint)
    DELETE od FROM OrderDetails od
    INNER JOIN Orders o ON od.OrderID = o.OrderID
    WHERE o.CreatedDate >= DATEADD(day, -1, GETDATE()) 
    AND o.ShippingAddress LIKE '%Test%';
    
    -- Delete test orders
    DELETE FROM Orders 
    WHERE CreatedDate >= DATEADD(day, -1, GETDATE()) 
    AND ShippingAddress LIKE '%Test%';
    
    -- Delete test products
    DELETE FROM Products 
    WHERE ProductName LIKE 'TestProduct_%' OR ProductName LIKE 'Test Widget%' OR ProductName LIKE 'Test Gadget%' OR ProductName LIKE 'Test Device%';
    
    -- Delete test customers
    DELETE FROM Customers 
    WHERE FirstName LIKE 'TestUser%' OR FirstName IN ('Alice', 'Bob', 'Carol') OR Email LIKE '%test.com';
    
    PRINT 'Test data removed from publisher';
    " 2>/dev/null
    
    echo -e "${GREEN}✓ Test data removed${NC}"
    echo -e "${YELLOW}Changes will replicate to subscriber automatically${NC}"
fi

# Show final status
echo -e "\n${BLUE}Final Environment Status:${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

echo -e "\n${YELLOW}Running containers:${NC}"
docker ps --filter "name=sqlserver" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No containers running"

echo -e "\n${YELLOW}Available volumes:${NC}"
docker volume ls --filter "name=sqlserver-replication" || echo "No volumes found"

echo -e "\n${BLUE}Cleanup completed!${NC}"

# Provide next steps
if docker ps --filter "name=sqlserver" -q | grep -q .; then
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo -e "- Containers are still running"
    echo -e "- Use ${GREEN}./scripts/monitor-replication.sh${NC} to check status"
    echo -e "- Use ${GREEN}./scripts/generate-test-data.sh${NC} to create test data"
else
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo -e "- Use ${GREEN}docker-compose up -d${NC} to start containers"
    echo -e "- Use ${GREEN}./scripts/setup-replication.sh${NC} to configure replication"
fi
