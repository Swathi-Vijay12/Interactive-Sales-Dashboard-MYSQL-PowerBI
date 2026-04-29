/*
=============================================================================
PROJECT: Executive Sales Analysis (2014-2017)
DATABASE: MySQL
DESCRIPTION: End-to-end data modeling and ETL process from raw sales data 
             to a finalized Star Schema.
=============================================================================
*/

-- --------------------------------------------------------------------------
-- 1. STAGING & INITIAL DATA SETUP
-- --------------------------------------------------------------------------
-- Moving raw data from staging to a working table
CREATE TABLE sales LIKE raw_sales;
INSERT INTO sales SELECT * FROM raw_sales;

-- --------------------------------------------------------------------------
-- 2. DIMENSION TABLE CREATION
-- --------------------------------------------------------------------------

-- Dim_Product: Extracting unique products
CREATE TABLE Dim_Product (
    ProductKey INT PRIMARY KEY AUTO_INCREMENT,
    ProductID VARCHAR(50),
    ProductName VARCHAR(255),
    Category VARCHAR(100),
    SubCategory VARCHAR(100)
);

INSERT INTO Dim_Product (ProductID, ProductName, Category, SubCategory)
SELECT DISTINCT `Product_ID`, `Product_Name`, `Category`, `Sub_Category`
FROM sales;

-- Dim_Customer: Extracting unique customers with State data
CREATE TABLE Dim_Customer (
    CustomerKey INT PRIMARY KEY AUTO_INCREMENT,
    CustomerID VARCHAR(50),
    CustomerName VARCHAR(255),
    Segment VARCHAR(50),
    State VARCHAR(100)
);

INSERT INTO Dim_Customer (CustomerID, CustomerName, Segment, State)
SELECT DISTINCT `Customer_ID`, `Customer_Name`, `Segment`, `State`
FROM sales;

-- --------------------------------------------------------------------------
-- 3. CALENDAR TABLE (TIME INTELLIGENCE)
-- --------------------------------------------------------------------------
-- Creating a continuous date table using Recursive CTE
CREATE TABLE Dim_Date (
    DateKey DATE PRIMARY KEY,
    Year INT,
    Quarter INT,
    Month INT,
    MonthName VARCHAR(20),
    Day INT,
    DayOfWeek VARCHAR(20),
    IsWeekend TINYINT(1)
);

SET SESSION cte_max_recursion_depth = 2000;

INSERT INTO Dim_Date
WITH RECURSIVE DateRange AS (
    SELECT '2014-01-01' AS CalendarDate
    UNION ALL
    SELECT CalendarDate + INTERVAL 1 DAY
    FROM DateRange
    WHERE CalendarDate < '2017-12-31'
)
SELECT 
    CalendarDate AS DateKey,
    YEAR(CalendarDate),
    QUARTER(CalendarDate),
    MONTH(CalendarDate),
    MONTHNAME(CalendarDate),
    DAY(CalendarDate),
    DAYNAME(CalendarDate),
    CASE WHEN DAYOFWEEK(CalendarDate) IN (1, 7) THEN 1 ELSE 0 END
FROM DateRange;

-- --------------------------------------------------------------------------
-- 4. FACT TABLE CREATION & ETL
-- --------------------------------------------------------------------------

CREATE TABLE Fact_Sales (
    SalesKey INT NOT NULL AUTO_INCREMENT,
    OrderID VARCHAR(50),
    OrderDate DATE,
    CustomerKey INT,
    ProductKey INT,
    SalesAmount DECIMAL(18,2),
    Quantity INT,
    Profit DECIMAL(18,2),
    PRIMARY KEY (SalesKey),
    FOREIGN KEY (CustomerKey) REFERENCES Dim_Customer(CustomerKey),
    FOREIGN KEY (ProductKey) REFERENCES Dim_Product(ProductKey)
);

-- Populating Fact table with standardized date parsing and joins
INSERT INTO Fact_Sales (OrderID, OrderDate, CustomerKey, ProductKey, SalesAmount, Quantity, Profit)
SELECT 
    s.`Order_ID`,
    -- Standardizing mixed text formats (smashes slashes and dashes into DATE format)
    STR_TO_DATE(REPLACE(REPLACE(s.`Order_Date`, '//', '-'), '/', '-'), '%m-%d-%Y'),
    c.CustomerKey,
    p.ProductKey,
    s.Sales,
    s.Quantity,
    s.Profit
FROM sales s
JOIN Dim_Customer c ON s.`Customer_ID` = c.CustomerID
JOIN Dim_Product p ON s.`Product_ID` = p.ProductID AND s.`Product_Name` = p.ProductName;

-- --------------------------------------------------------------------------
-- 5. DATA VALIDATION (AUDIT QUERIES)
-- --------------------------------------------------------------------------
-- Ensure Sales amounts match between Raw and Fact table
SELECT 'Staging Sum' as Source, SUM(Sales) FROM sales
UNION ALL
SELECT 'Fact Sum' as Source, SUM(SalesAmount) FROM Fact_Sales;

-- Check for any NULL dates that failed conversion
SELECT COUNT(*) as NullDateCount FROM Fact_Sales WHERE OrderDate IS NULL;
