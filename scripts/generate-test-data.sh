#!/bin/bash

# SQL Server Replication Test Data Generation Script
# This script generates test data to verify replication functionality

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

# SQL Server tools path (updated for 2022)
SQLCMD_PATH="/opt/mssql-tools18/bin/sqlcmd"
SQLCMD_ARGS="-C" # Trust server certificate

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}SQL Server Replication Test Data Generator${NC}"
echo -e "${BLUE}===============================================${NC}"

# Function to execute SQL query
execute_sql() {
    local container=$1
    local query=$2
    local description=$3
    
    echo -e "${YELLOW}$description...${NC}"
    
    if docker exec $container $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$query" $SQLCMD_ARGS > /dev/null 2>&1; then
        echo -e "${GREEN}✓ $description completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ $description failed${NC}"
        return 1
    fi
}

# Function to get count
get_count() {
    local container=$1
    local query=$2
    docker exec $container $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$query" -h -1 -W $SQLCMD_ARGS 2>/dev/null | tr -d ' \r\n' | tail -1
}

# Function to display counts
show_counts() {
    local title=$1
    echo -e "\n${BLUE}$title${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    
    local pub_customers=$(get_count $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Customers")
    local sub_customers=$(get_count $SUBSCRIBER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Customers")
    
    local pub_products=$(get_count $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Products")
    local sub_products=$(get_count $SUBSCRIBER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Products")
    
    local pub_orders=$(get_count $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Orders")
    local sub_orders=$(get_count $SUBSCRIBER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Orders")
    
    echo -e "Table          Publisher    Subscriber"
    echo -e "--------------------------------"
    echo -e "Customers      $pub_customers           $sub_customers"
    echo -e "Products       $pub_products           $sub_products"
    echo -e "Orders         $pub_orders           $sub_orders"
}

# Show initial counts
show_counts "Initial Record Counts"

# Generate test customers
echo -e "\n${BLUE}Step 1: Generating Test Customers${NC}"
CUSTOMER_SQL="
USE ReplicationDemo;
DECLARE @StartTime DATETIME2 = GETDATE();
INSERT INTO Customers (FirstName, LastName, Email, Phone, Address, City, State, ZipCode)
VALUES 
    ('TestUser' + CAST(DATEPART(second, @StartTime) AS VARCHAR), 'LastName1', 'test1_' + CAST(@StartTime AS VARCHAR) + '@example.com', '555-TEST1', '123 Test Street', 'TestCity', 'TS', '12345'),
    ('TestUser' + CAST(DATEPART(second, @StartTime) + 1 AS VARCHAR), 'LastName2', 'test2_' + CAST(@StartTime AS VARCHAR) + '@example.com', '555-TEST2', '456 Test Avenue', 'TestTown', 'TT', '67890'),
    ('TestUser' + CAST(DATEPART(second, @StartTime) + 2 AS VARCHAR), 'LastName3', 'test3_' + CAST(@StartTime AS VARCHAR) + '@example.com', '555-TEST3', '789 Test Boulevard', 'TestVille', 'TV', '54321');
PRINT 'Added 3 test customers at ' + CAST(@StartTime AS VARCHAR);
"

execute_sql $PUBLISHER_CONTAINER "$CUSTOMER_SQL" "Adding test customers to publisher"

# Generate test products
echo -e "\n${BLUE}Step 2: Generating Test Products${NC}"
PRODUCT_SQL="
USE ReplicationDemo;
DECLARE @StartTime DATETIME2 = GETDATE();
INSERT INTO Products (ProductName, CategoryID, Description, Price, StockQuantity)
VALUES 
    ('TestProduct_' + FORMAT(@StartTime, 'yyyyMMdd_HHmmss') + '_A', 99, 'Test product A for replication testing', 25.99, 100),
    ('TestProduct_' + FORMAT(@StartTime, 'yyyyMMdd_HHmmss') + '_B', 99, 'Test product B for replication testing', 45.99, 200),
    ('TestProduct_' + FORMAT(@StartTime, 'yyyyMMdd_HHmmss') + '_C', 99, 'Test product C for replication testing', 65.99, 150);
PRINT 'Added 3 test products at ' + CAST(@StartTime AS VARCHAR);
"

execute_sql $PUBLISHER_CONTAINER "$PRODUCT_SQL" "Adding test products to publisher"

# Wait for replication
echo -e "\n${YELLOW}Waiting 10 seconds for replication to propagate...${NC}"
sleep 10

# Show intermediate counts
show_counts "After Adding Customers and Products"

# Generate test orders
echo -e "\n${BLUE}Step 3: Generating Test Orders${NC}"
ORDER_SQL="
USE ReplicationDemo;
DECLARE @StartTime DATETIME2 = GETDATE();
DECLARE @CustomerID INT, @OrderID INT;

-- Get a random customer
SELECT TOP 1 @CustomerID = CustomerID FROM Customers ORDER BY NEWID();

-- Insert test order
INSERT INTO Orders (CustomerID, TotalAmount, Status, ShippingAddress)
VALUES (@CustomerID, 71.98, 'Processing', 'Test Shipping Address for Order at ' + CAST(@StartTime AS VARCHAR));

SET @OrderID = SCOPE_IDENTITY();

-- Insert order details
INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
SELECT TOP 2 @OrderID, ProductID, 1, Price
FROM Products 
WHERE ProductName LIKE 'TestProduct_%'
ORDER BY NEWID();

PRINT 'Added test order with ID ' + CAST(@OrderID AS VARCHAR) + ' at ' + CAST(@StartTime AS VARCHAR);
"

execute_sql $PUBLISHER_CONTAINER "$ORDER_SQL" "Adding test order to publisher"

# Update existing data to test replication of updates
echo -e "\n${BLUE}Step 4: Testing Updates${NC}"
UPDATE_SQL="
USE ReplicationDemo;
DECLARE @StartTime DATETIME2 = GETDATE();

-- Update a product price
UPDATE Products 
SET Price = Price + 5.00,
    ModifiedDate = @StartTime
WHERE ProductName LIKE 'TestProduct_%';

-- Update a customer phone
UPDATE TOP(1) Customers 
SET Phone = '555-UPDATED-' + FORMAT(@StartTime, 'HHmmss'),
    ModifiedDate = @StartTime
WHERE FirstName LIKE 'TestUser%';

PRINT 'Updated test data at ' + CAST(@StartTime AS VARCHAR);
"

execute_sql $PUBLISHER_CONTAINER "$UPDATE_SQL" "Updating test data on publisher"

# Wait for replication
echo -e "\n${YELLOW}Waiting 15 seconds for all changes to replicate...${NC}"
sleep 15

# Show final counts
show_counts "Final Record Counts"

# Verify replication with detailed check
echo -e "\n${BLUE}Step 5: Detailed Replication Verification${NC}"

# Check latest customers
echo -e "\n${YELLOW}Latest customers on both servers:${NC}"
LATEST_CUSTOMERS="USE ReplicationDemo; SELECT TOP 3 CustomerID, FirstName, LastName, Email, CreatedDate FROM Customers WHERE FirstName LIKE 'TestUser%' ORDER BY CreatedDate DESC;"

echo -e "\n${YELLOW}Publisher:${NC}"
docker exec $PUBLISHER_CONTAINER $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$LATEST_CUSTOMERS" $SQLCMD_ARGS

echo -e "\n${YELLOW}Subscriber:${NC}"
docker exec $SUBSCRIBER_CONTAINER $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$LATEST_CUSTOMERS" $SQLCMD_ARGS

# Check latest products
echo -e "\n${YELLOW}Latest products on both servers:${NC}"
LATEST_PRODUCTS="USE ReplicationDemo; SELECT TOP 3 ProductID, ProductName, Price, ModifiedDate FROM Products WHERE ProductName LIKE 'TestProduct_%' ORDER BY CreatedDate DESC;"

echo -e "\n${YELLOW}Publisher:${NC}"
docker exec $PUBLISHER_CONTAINER $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$LATEST_PRODUCTS" $SQLCMD_ARGS

echo -e "\n${YELLOW}Subscriber:${NC}"
docker exec $SUBSCRIBER_CONTAINER $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$LATEST_PRODUCTS" $SQLCMD_ARGS

# Check latest orders
echo -e "\n${YELLOW}Latest orders on both servers:${NC}"
LATEST_ORDERS="USE ReplicationDemo; SELECT TOP 3 o.OrderID, o.CustomerID, o.TotalAmount, o.Status, o.CreatedDate FROM Orders o WHERE o.CreatedDate >= DATEADD(minute, -5, GETDATE()) ORDER BY o.CreatedDate DESC;"

echo -e "\n${YELLOW}Publisher:${NC}"
docker exec $PUBLISHER_CONTAINER $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$LATEST_ORDERS" $SQLCMD_ARGS

echo -e "\n${YELLOW}Subscriber:${NC}"
docker exec $SUBSCRIBER_CONTAINER $SQLCMD_PATH -S localhost -U sa -P "$SA_PASSWORD" -Q "$LATEST_ORDERS" $SQLCMD_ARGS

# Summary
echo -e "\n${BLUE}Step 6: Test Summary${NC}"
echo -e "${YELLOW}----------------------------------------${NC}"

# Final count comparison
pub_total=$(get_count $PUBLISHER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Customers WHERE FirstName LIKE 'TestUser%'")
sub_total=$(get_count $SUBSCRIBER_CONTAINER "USE ReplicationDemo; SELECT COUNT(*) FROM Customers WHERE FirstName LIKE 'TestUser%'")

echo -e "Test customers created: $pub_total (Publisher), $sub_total (Subscriber)"

if [ "$pub_total" = "$sub_total" ] && [ "$pub_total" -gt "0" ]; then
    echo -e "${GREEN}✓ Test data replication successful!${NC}"
    echo -e "${GREEN}✓ All test records appear to be synchronized${NC}"
else
    echo -e "${RED}✗ Test data replication may have issues${NC}"
    echo -e "${YELLOW}⚠ This could be due to replication lag - wait a few more seconds and check again${NC}"
fi

echo -e "\n${BLUE}Test data generation complete!${NC}"
echo -e "${YELLOW}You can run this script multiple times to generate more test data.${NC}"
echo -e "${YELLOW}Use the monitor-replication.sh script to check detailed replication status.${NC}"
