-- Create Sample Database and Tables for Replication Demo
-- This script creates the sample database structure used in replication

USE master;
GO

-- Create the sample database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ReplicationDemo')
BEGIN
    CREATE DATABASE ReplicationDemo;
    PRINT 'Database ReplicationDemo created successfully';
END
ELSE
BEGIN
    PRINT 'Database ReplicationDemo already exists';
END
GO

USE ReplicationDemo;
GO

-- Create Customers table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Customers' AND xtype='U')
BEGIN
    CREATE TABLE Customers (
        CustomerID int IDENTITY(1,1) PRIMARY KEY,
        FirstName nvarchar(50) NOT NULL,
        LastName nvarchar(50) NOT NULL,
        Email nvarchar(100) UNIQUE NOT NULL,
        Phone nvarchar(20),
        Address nvarchar(200),
        City nvarchar(50),
        State nvarchar(50),
        ZipCode nvarchar(10),
        CreatedDate datetime2 DEFAULT GETDATE(),
        ModifiedDate datetime2 DEFAULT GETDATE()
    );
    PRINT 'Customers table created successfully';
END
GO

-- Create Products table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Products' AND xtype='U')
BEGIN
    CREATE TABLE Products (
        ProductID int IDENTITY(1,1) PRIMARY KEY,
        ProductName nvarchar(100) NOT NULL,
        CategoryID int,
        Description nvarchar(500),
        Price decimal(10,2) NOT NULL,
        StockQuantity int DEFAULT 0,
        IsActive bit DEFAULT 1,
        CreatedDate datetime2 DEFAULT GETDATE(),
        ModifiedDate datetime2 DEFAULT GETDATE()
    );
    PRINT 'Products table created successfully';
END
GO

-- Create Orders table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Orders' AND xtype='U')
BEGIN
    CREATE TABLE Orders (
        OrderID int IDENTITY(1,1) PRIMARY KEY,
        CustomerID int NOT NULL,
        OrderDate datetime2 DEFAULT GETDATE(),
        TotalAmount decimal(10,2) NOT NULL,
        Status nvarchar(20) DEFAULT 'Pending',
        ShippingAddress nvarchar(200),
        CreatedDate datetime2 DEFAULT GETDATE(),
        ModifiedDate datetime2 DEFAULT GETDATE(),
        FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
    );
    PRINT 'Orders table created successfully';
END
GO

-- Create OrderDetails table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='OrderDetails' AND xtype='U')
BEGIN
    CREATE TABLE OrderDetails (
        OrderDetailID int IDENTITY(1,1) PRIMARY KEY,
        OrderID int NOT NULL,
        ProductID int NOT NULL,
        Quantity int NOT NULL,
        UnitPrice decimal(10,2) NOT NULL,
        LineTotal AS (Quantity * UnitPrice),
        FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
        FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
    );
    PRINT 'OrderDetails table created successfully';
END
GO

-- Insert sample data into Customers
INSERT INTO Customers (FirstName, LastName, Email, Phone, Address, City, State, ZipCode)
VALUES 
    ('John', 'Doe', 'john.doe@email.com', '555-1234', '123 Main St', 'Anytown', 'CA', '12345'),
    ('Jane', 'Smith', 'jane.smith@email.com', '555-5678', '456 Oak Ave', 'Somewhere', 'NY', '67890'),
    ('Mike', 'Johnson', 'mike.johnson@email.com', '555-9012', '789 Pine Rd', 'Elsewhere', 'TX', '54321'),
    ('Sarah', 'Williams', 'sarah.williams@email.com', '555-3456', '321 Elm St', 'Nowhere', 'FL', '98765'),
    ('David', 'Brown', 'david.brown@email.com', '555-7890', '654 Maple Dr', 'Anywhere', 'WA', '13579');

-- Insert sample data into Products
INSERT INTO Products (ProductName, CategoryID, Description, Price, StockQuantity)
VALUES 
    ('Laptop Computer', 1, 'High-performance laptop for business use', 1299.99, 50),
    ('Wireless Mouse', 1, 'Ergonomic wireless mouse with USB receiver', 29.99, 200),
    ('Keyboard', 1, 'Mechanical keyboard with RGB lighting', 89.99, 150),
    ('Monitor', 1, '27-inch 4K display monitor', 399.99, 75),
    ('Webcam', 1, 'HD webcam for video conferencing', 79.99, 100),
    ('Headphones', 2, 'Noise-cancelling wireless headphones', 199.99, 80),
    ('Smartphone', 2, 'Latest generation smartphone', 899.99, 60),
    ('Tablet', 2, '10-inch tablet with stylus support', 549.99, 40);

-- Insert sample data into Orders
INSERT INTO Orders (CustomerID, TotalAmount, Status, ShippingAddress)
VALUES 
    (1, 1389.98, 'Completed', '123 Main St, Anytown, CA 12345'),
    (2, 119.98, 'Shipped', '456 Oak Ave, Somewhere, NY 67890'),
    (3, 899.99, 'Processing', '789 Pine Rd, Elsewhere, TX 54321'),
    (4, 629.98, 'Pending', '321 Elm St, Nowhere, FL 98765');

-- Insert sample data into OrderDetails
INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
VALUES 
    (1, 1, 1, 1299.99),  -- Laptop
    (1, 2, 3, 29.99),    -- Wireless Mouse
    (2, 3, 1, 89.99),    -- Keyboard
    (2, 2, 1, 29.99),    -- Wireless Mouse
    (3, 7, 1, 899.99),   -- Smartphone
    (4, 4, 1, 399.99),   -- Monitor
    (4, 6, 1, 199.99),   -- Headphones
    (4, 2, 1, 29.99);    -- Wireless Mouse

PRINT 'Sample data inserted successfully';
GO

-- Create indexes for better performance
CREATE NONCLUSTERED INDEX IX_Customers_Email ON Customers(Email);
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON Orders(CustomerID);
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON Orders(OrderDate);
CREATE NONCLUSTERED INDEX IX_OrderDetails_OrderID ON OrderDetails(OrderID);
CREATE NONCLUSTERED INDEX IX_OrderDetails_ProductID ON OrderDetails(ProductID);

PRINT 'Indexes created successfully';
GO
