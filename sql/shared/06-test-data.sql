-- Test Data Generation for Replication Testing
-- Run this on the Publisher to test replication functionality

USE ReplicationDemo;
GO

-- Insert test customers
INSERT INTO Customers (FirstName, LastName, Email, Phone, Address, City, State, ZipCode)
VALUES 
    ('Alice', 'Cooper', 'alice.cooper@test.com', '555-1111', '111 Test St', 'TestCity', 'TC', '11111'),
    ('Bob', 'Builder', 'bob.builder@test.com', '555-2222', '222 Build Ave', 'BuildTown', 'BT', '22222'),
    ('Carol', 'Singer', 'carol.singer@test.com', '555-3333', '333 Music Ln', 'Harmony', 'HM', '33333');

PRINT 'Test customers added - check subscriber for replication';

-- Insert test products
INSERT INTO Products (ProductName, CategoryID, Description, Price, StockQuantity)
VALUES 
    ('Test Widget A', 3, 'A test widget for replication testing', 19.99, 1000),
    ('Test Gadget B', 3, 'A test gadget for replication testing', 39.99, 500),
    ('Test Device C', 3, 'A test device for replication testing', 59.99, 250);

PRINT 'Test products added - check subscriber for replication';

-- Update existing data to test replication of updates
UPDATE Products 
SET Price = Price * 1.1, 
    ModifiedDate = GETDATE()
WHERE ProductID <= 3;

PRINT 'Product prices updated - check subscriber for replication';

UPDATE Customers 
SET Phone = '555-UPDATED',
    ModifiedDate = GETDATE()
WHERE CustomerID = 1;

PRINT 'Customer phone updated - check subscriber for replication';

-- Insert test orders
DECLARE @CustomerID int = (SELECT TOP 1 CustomerID FROM Customers ORDER BY NEWID());
DECLARE @OrderID int;

INSERT INTO Orders (CustomerID, TotalAmount, Status, ShippingAddress)
VALUES (@CustomerID, 79.98, 'Processing', 'Test Address for Replication');

SET @OrderID = SCOPE_IDENTITY();

INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
VALUES 
    (@OrderID, (SELECT TOP 1 ProductID FROM Products WHERE ProductName LIKE 'Test%' ORDER BY NEWID()), 2, 19.99),
    (@OrderID, (SELECT TOP 1 ProductID FROM Products WHERE ProductName LIKE 'Test%' ORDER BY NEWID()), 1, 39.99);

PRINT 'Test order created - check subscriber for replication';

-- Show what we just created
SELECT 'Latest Customers' AS TableName, CustomerID, FirstName, LastName, Email, CreatedDate
FROM Customers 
WHERE CreatedDate >= DATEADD(minute, -5, GETDATE())
UNION ALL
SELECT 'Latest Products', ProductID, ProductName, '', '', CreatedDate
FROM Products 
WHERE CreatedDate >= DATEADD(minute, -5, GETDATE())
UNION ALL
SELECT 'Latest Orders', OrderID, CAST(CustomerID AS nvarchar), CAST(TotalAmount AS nvarchar), Status, CreatedDate
FROM Orders 
WHERE CreatedDate >= DATEADD(minute, -5, GETDATE());

PRINT 'Test data generation completed - please check subscriber database for replicated data';
PRINT 'You can run this script multiple times to generate more test data';

GO
