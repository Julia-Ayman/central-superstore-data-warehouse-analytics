CREATE DATABASE CentralSuperstoreDW;
GO
USE CentralSuperstoreDW;
GO

-- Create the four warehouse layers

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze')
    EXEC('CREATE SCHEMA bronze');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO

--check

SELECT
    name AS SchemaName
FROM sys.schemas
WHERE name IN ('staging', 'bronze', 'silver', 'gold')
ORDER BY name;
-- Create the staging table
IF NOT EXISTS
(SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'staging' AND t.name = 'CentralSuperstore')
BEGIN
CREATE TABLE dbo.stg_CentralSuperstore
(
    Row_ID INT,
    Order_ID VARCHAR(50),
    Order_Date VARCHAR(20),
    Ship_Date VARCHAR(20),
    Ship_Mode VARCHAR(50),
    Customer_ID VARCHAR(50),
    Customer_Name VARCHAR(100),
    Segment VARCHAR(50),
    Country VARCHAR(100),
    City VARCHAR(100),
    State VARCHAR(100),
    Postal_Code VARCHAR(20),
    Region VARCHAR(50),
    Product_ID VARCHAR(50),
    Category VARCHAR(50),
    Sub_Category VARCHAR(50),
    Product_Name VARCHAR(255),
    Sales DECIMAL(18,4),
    Quantity INT,
    Discount DECIMAL(5,4),
    Profit DECIMAL(18,4)
);
END;
GO

ALTER SCHEMA staging
TRANSFER dbo.stg_CentralSuperstore;
GO

TRUNCATE TABLE dbo.stg_CentralSuperstore;
BULK INSERT dbo.stg_CentralSuperstore
FROM 'C:\Users\Kimo Store\Downloads\Central_Superstore.csv'
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDQUOTE = '"',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
WHERE t.name = 'stg_CentralSuperstore';

-- BRONZE LAYER------------------------------------------------------------------------------------------------------------------------------

IF NOT EXISTS
(SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'bronze' AND t.name = 'CentralSuperstore')
BEGIN
    CREATE TABLE bronze.CentralSuperstore
    (
        Bronze_ID INT IDENTITY(1,1),

        Row_ID VARCHAR(50),
        Order_ID VARCHAR(50),
        Order_Date VARCHAR(50),
        Ship_Date VARCHAR(50),
        Ship_Mode VARCHAR(50),
        Customer_ID VARCHAR(50),
        Customer_Name VARCHAR(100),
        Segment VARCHAR(50),
        Country VARCHAR(100),
        City VARCHAR(100),
        State VARCHAR(100),
        Postal_Code VARCHAR(50),
        Region VARCHAR(50),
        Product_ID VARCHAR(50),
        Category VARCHAR(50),
        Sub_Category VARCHAR(50),
        Product_Name VARCHAR(255),
        Sales VARCHAR(50),
        Quantity VARCHAR(50),
        Discount VARCHAR(50),
        Profit VARCHAR(50),

        LoadDate DATETIME DEFAULT GETDATE()
    );
END;
GO
--Load Staging → Bronze
INSERT INTO bronze.CentralSuperstore
(
    Row_ID,
    Order_ID,
    Order_Date,
    Ship_Date,
    Ship_Mode,
    Customer_ID,
    Customer_Name,
    Segment,
    Country,
    City,
    State,
    Postal_Code,
    Region,
    Product_ID,
    Category,
    Sub_Category,
    Product_Name,
    Sales,
    Quantity,
    Discount,
    Profit
)
SELECT
    CAST(Row_ID AS VARCHAR(50)),
    Order_ID,
    Order_Date,
    Ship_Date,
    Ship_Mode,
    Customer_ID,
    Customer_Name,
    Segment,
    Country,
    City,
    State,
    Postal_Code,
    Region,
    Product_ID,
    Category,
    Sub_Category,
    Product_Name,
    CAST(Sales AS VARCHAR(50)),
    CAST(Quantity AS VARCHAR(50)),
    CAST(Discount AS VARCHAR(50)),
    CAST(Profit AS VARCHAR(50))
FROM staging.stg_CentralSuperstore;
GO

--Silver layer----------------------------------------------------------------------------------------------------
IF NOT EXISTS
(
    SELECT 1
    FROM sys.tables t
    JOIN sys.schemas s
        ON t.schema_id = s.schema_id
    WHERE s.name = 'silver'
      AND t.name = 'CentralSuperstore'
)
BEGIN
    CREATE TABLE silver.CentralSuperstore
    (
        Row_ID INT NOT NULL,
    Order_ID VARCHAR(50) NOT NULL,
    Order_Date DATE,
    Ship_Date DATE,
    Ship_Mode VARCHAR(50),
    Customer_ID VARCHAR(50),
    Customer_Name VARCHAR(100),
    Segment VARCHAR(50),
    Country VARCHAR(100),
    City VARCHAR(100),
    State VARCHAR(100),
    Postal_Code VARCHAR(20),
    Region VARCHAR(50),
    Product_ID VARCHAR(50),
    Category VARCHAR(50),
    Sub_Category VARCHAR(50),
    Product_Name VARCHAR(255),
    Sales DECIMAL(18,4),
    Quantity INT,
    Discount DECIMAL(5,4),
    Profit DECIMAL(18,4),

    has_missing_value BIT NOT NULL DEFAULT 0,
    has_invalid_value BIT NOT NULL DEFAULT 0,
    has_outlier_value BIT NOT NULL DEFAULT 0
);
END;
GO
-- Keep only the latest version
WITH latest_rows AS
(
    SELECT
        *,
        ROW_NUMBER() OVER
        (
            PARTITION BY Row_ID
            ORDER BY Bronze_ID DESC
        ) AS rn
    FROM bronze.CentralSuperstore
    WHERE Row_ID IS NOT NULL
),

-- Turn the raw Bronze strings into clean, usable data types
cleaned AS
(
    SELECT
        Row_ID,
        LTRIM(RTRIM(Order_ID)) AS Order_ID,
        TRY_CONVERT(DATE, Order_Date, 103) AS Order_Date,
        TRY_CONVERT(DATE, Ship_Date, 103) AS Ship_Date,
        LTRIM(RTRIM(Ship_Mode)) AS Ship_Mode,
        LTRIM(RTRIM(Customer_ID)) AS Customer_ID,
        LTRIM(RTRIM(Customer_Name)) AS Customer_Name,
        LTRIM(RTRIM(Segment)) AS Segment,
        LTRIM(RTRIM(Country)) AS Country,
        LTRIM(RTRIM(City)) AS City,
        LTRIM(RTRIM(State)) AS State,
        LTRIM(RTRIM(Postal_Code)) AS Postal_Code,
        LTRIM(RTRIM(Region)) AS Region,
        LTRIM(RTRIM(Product_ID)) AS Product_ID,
        LTRIM(RTRIM(Category)) AS Category,
        LTRIM(RTRIM(Sub_Category)) AS Sub_Category,
        LTRIM(RTRIM(Product_Name)) AS Product_Name,
        TRY_CONVERT(DECIMAL(18,4), Sales) AS Sales,
        TRY_CONVERT(INT, Quantity) AS Quantity,
        TRY_CONVERT(DECIMAL(5,4), Discount) AS Discount,
        TRY_CONVERT(DECIMAL(18,4), Profit) AS Profit
    FROM latest_rows
    WHERE rn = 1
),

--outliers
sales_bounds AS
(
    SELECT
        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY Sales)
            OVER () AS Q1,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY Sales)
            OVER () AS Q3

    FROM cleaned
),

--calculates limits
sales_limits AS
(
    SELECT
        Q1,
        Q3,
        Q3 - Q1 AS IQR,
        Q1 - 1.5 * (Q3 - Q1) AS lower_limit,
        Q3 + 1.5 * (Q3 - Q1) AS upper_limit
    FROM sales_bounds
),
-- Check the cleaned data for missing or invalid values
flagged AS
(
    SELECT
        *,
        
        CASE
            WHEN Order_ID IS NULL
              OR Customer_ID IS NULL
              OR Product_ID IS NULL
              OR Order_Date IS NULL
              OR Sales IS NULL
              OR Quantity IS NULL
              OR Profit IS NULL
            THEN 1
            ELSE 0
        END AS has_missing_value,

        CASE
            WHEN Ship_Date < Order_Date
              OR Quantity <= 0
              OR Discount < 0
              OR Discount > 1
            THEN 1
            ELSE 0
        END AS has_invalid_value,
      CASE
          WHEN Sales < -263.468
             OR Sales > 478.1 THEN 1
             ELSE 0
          END AS has_outlier_value
    FROM cleaned
)
--merge from bronze to silver
MERGE silver.CentralSuperstore AS target
USING flagged AS source
    ON target.Row_ID = source.Row_ID

WHEN MATCHED THEN
    UPDATE SET
        target.Order_ID = source.Order_ID,
        target.Order_Date = source.Order_Date,
        target.Ship_Date = source.Ship_Date,
        target.Ship_Mode = source.Ship_Mode,
        target.Customer_ID = source.Customer_ID,
        target.Customer_Name = source.Customer_Name,
        target.Segment = source.Segment,
        target.Country = source.Country,
        target.City = source.City,
        target.State = source.State,
        target.Postal_Code = source.Postal_Code,
        target.Region = source.Region,
        target.Product_ID = source.Product_ID,
        target.Category = source.Category,
        target.Sub_Category = source.Sub_Category,
        target.Product_Name = source.Product_Name,
        target.Sales = source.Sales,
        target.Quantity = source.Quantity,
        target.Discount = source.Discount,
        target.Profit = source.Profit,
        target.has_missing_value = source.has_missing_value,
        target.has_invalid_value = source.has_invalid_value,
        target.has_outlier_value = source.has_outlier_value

WHEN NOT MATCHED BY TARGET THEN
    INSERT
    (
        Row_ID,
        Order_ID,
        Order_Date,
        Ship_Date,
        Ship_Mode,
        Customer_ID,
        Customer_Name,
        Segment,
        Country,
        City,
        State,
        Postal_Code,
        Region,
        Product_ID,
        Category,
        Sub_Category,
        Product_Name,
        Sales,
        Quantity,
        Discount,
        Profit,
        has_missing_value,
        has_invalid_value,
        has_outlier_value
    )
    VALUES
    (
        source.Row_ID,
        source.Order_ID,
        source.Order_Date,
        source.Ship_Date,
        source.Ship_Mode,
        source.Customer_ID,
        source.Customer_Name,
        source.Segment,
        source.Country,
        source.City,
        source.State,
        source.Postal_Code,
        source.Region,
        source.Product_ID,
        source.Category,
        source.Sub_Category,
        source.Product_Name,
        source.Sales,
        source.Quantity,
        source.Discount,
        source.Profit,
        source.has_missing_value,
        source.has_invalid_value,
        source.has_outlier_value
    );

GO

--GOLD LAYER------------------------------------------------------------------------------------------------------------
-- DIMENSION TABLES
-- Customer dimension

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'DimCustomer')
BEGIN
    CREATE TABLE gold.DimCustomer
    (
        CustomerKey INT IDENTITY(1,1) PRIMARY KEY,
        Customer_ID VARCHAR(50) NOT NULL,
        Customer_Name VARCHAR(100) NOT NULL,
        Segment VARCHAR(50) NOT NULL,
        CONSTRAINT UQ_DimCustomer_CustomerID UNIQUE (Customer_ID)
    );
END;
GO

--DimProduct
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'DimProduct')
BEGIN
    CREATE TABLE gold.DimProduct
    (
        ProductKey INT IDENTITY(1,1) PRIMARY KEY,
        Product_ID VARCHAR(50) NOT NULL,
        Product_Name VARCHAR(255) NOT NULL,
        Category VARCHAR(50) NOT NULL,
        Sub_Category VARCHAR(50) NOT NULL,
        CONSTRAINT UQ_DimProduct
            UNIQUE (Product_ID, Product_Name, Category, Sub_Category)
    );
END;
GO
--DimDate
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id  WHERE s.name = 'gold' AND t.name = 'DimDate')
BEGIN
    CREATE TABLE gold.DimDate
    (
        DateKey INT PRIMARY KEY,
        FullDate DATE NOT NULL,
        Year INT NOT NULL,
        Quarter INT NOT NULL,
        Month INT NOT NULL,
        MonthName VARCHAR(20) NOT NULL
    );
END;
GO
--DimLocation
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'DimLocation')
BEGIN
    CREATE TABLE gold.DimLocation
    (
        LocationKey INT IDENTITY(1,1) PRIMARY KEY,
        Country VARCHAR(100) NOT NULL,
        City VARCHAR(100) NOT NULL,
        State VARCHAR(100) NOT NULL,
        PostalCode VARCHAR(20) NOT NULL,
        Region VARCHAR(50) NOT NULL,
        CONSTRAINT UQ_DimLocation
            UNIQUE (Country, City, State, PostalCode, Region)
    );
END;
GO
--DimShipping
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'DimShipping')
BEGIN
    CREATE TABLE gold.DimShipping
    (
        ShippingKey INT IDENTITY(1,1) PRIMARY KEY,
        Ship_Mode VARCHAR(50) NOT NULL,
        CONSTRAINT UQ_DimShipping_ShipMode UNIQUE (Ship_Mode)
    );
END;
GO

--load the data to dim tables
--Load DimCustomer
INSERT INTO gold.DimCustomer
(
    Customer_ID,
    Customer_Name,
    Segment
)
SELECT DISTINCT
    s.Customer_ID,
    s.Customer_Name,
    s.Segment
FROM silver.CentralSuperstore s
WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.DimCustomer d
    WHERE d.Customer_ID = s.Customer_ID
);
GO
--Load DimProduct
INSERT INTO gold.DimProduct
(
    Product_ID,
    Product_Name,
    Category,
    Sub_Category
)
SELECT DISTINCT
    s.Product_ID,
    s.Product_Name,
    s.Category,
    s.Sub_Category
FROM silver.CentralSuperstore s
WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.DimProduct d
    WHERE d.Product_ID = s.Product_ID
      AND d.Product_Name = s.Product_Name
      AND d.Category = s.Category
      AND d.Sub_Category = s.Sub_Category
);
GO
--which products have conflicting information
SELECT
    Product_ID,
    COUNT(DISTINCT Product_Name) AS ProductNameCount,
    COUNT(DISTINCT Category) AS CategoryCount,
    COUNT(DISTINCT Sub_Category) AS SubCategoryCount
FROM silver.CentralSuperstore
GROUP BY Product_ID
HAVING COUNT(DISTINCT Product_Name) > 1
    OR COUNT(DISTINCT Category) > 1
    OR COUNT(DISTINCT Sub_Category) > 1
ORDER BY Product_ID;

--Some Product_IDs are associated with two different Product_Names.
SELECT
    Product_ID,
    Product_Name,
    Category,
    Sub_Category,
    COUNT(*) AS RowCount1
FROM silver.CentralSuperstore
WHERE Product_ID = 'FUR-CH-10001146'
GROUP BY
    Product_ID,
    Product_Name,
    Category,
    Sub_Category
ORDER BY Product_Name;


--Load DimLocation
INSERT INTO gold.DimLocation
(
    Country,
    City,
    State,
    PostalCode,
    Region
)
SELECT DISTINCT
    s.Country,
    s.City,
    s.State,
    s.Postal_Code,
    s.Region
FROM silver.CentralSuperstore s
WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.DimLocation d
    WHERE d.Country = s.Country
      AND d.City = s.City
      AND d.State = s.State
      AND d.PostalCode = s.Postal_Code
      AND d.Region = s.Region
);
GO
--Load DimShipping
INSERT INTO gold.DimShipping
(
    Ship_Mode
)
SELECT DISTINCT
    s.Ship_Mode
FROM silver.CentralSuperstore s
WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.DimShipping d
    WHERE d.Ship_Mode = s.Ship_Mode
);
GO

--Load DimDate
INSERT INTO gold.DimDate
(
    DateKey,
    FullDate,
    Year,
    Quarter,
    Month,
    MonthName
)
SELECT
    CONVERT(INT, CONVERT(VARCHAR(8), d.FullDate, 112)) AS DateKey,
    d.FullDate,
    YEAR(d.FullDate),
    DATEPART(QUARTER, d.FullDate),
    MONTH(d.FullDate),
    DATENAME(MONTH, d.FullDate)
FROM
(
    SELECT TRY_CONVERT(DATE, Order_Date, 103) AS FullDate
    FROM silver.CentralSuperstore s

    UNION

    SELECT TRY_CONVERT(DATE, Ship_Date, 103) AS FullDate
    FROM silver.CentralSuperstore s
) d
WHERE d.FullDate IS NOT NULL
  AND NOT EXISTS
(
    SELECT 1
    FROM gold.DimDate dd
    WHERE dd.FullDate = d.FullDate
);
GO

--missing date data
SELECT
    DATEADD(DAY, 1, d.FullDate) AS MissingDate
FROM gold.DimDate d
LEFT JOIN gold.DimDate nextDate
    ON nextDate.FullDate = DATEADD(DAY, 1, d.FullDate)
WHERE d.FullDate < (SELECT MAX(FullDate) FROM gold.DimDate)
  AND nextDate.FullDate IS NULL
ORDER BY MissingDate;

--check if dim date is complete

SELECT
    MIN(FullDate) AS FirstDate,
    MAX(FullDate) AS LastDate,
    COUNT(*) AS CurrentRows,
    DATEDIFF(DAY, MIN(FullDate), MAX(FullDate)) + 1 AS ExpectedRows
FROM gold.DimDate;

--we have 406 missing dates that dates we don't have orders at it but we shoud have it in the table
--insert these 406 missing dates
;WITH DateLimits AS
(
    SELECT
        MIN(FullDate) AS FirstDate,
        MAX(FullDate) AS LastDate
    FROM gold.DimDate
),
DateRange AS
(
    SELECT FirstDate AS FullDate
    FROM DateLimits

    UNION ALL

    SELECT DATEADD(DAY, 1, d.FullDate)
    FROM DateRange d
    CROSS JOIN DateLimits l
    WHERE d.FullDate < l.LastDate
)
INSERT INTO gold.DimDate
(
    DateKey,
    FullDate,
    Year,
    Quarter,
    Month,
    MonthName
)
SELECT
    CONVERT(INT, CONVERT(VARCHAR(8), FullDate, 112)),
    FullDate,
    YEAR(FullDate),
    DATEPART(QUARTER, FullDate),
    MONTH(FullDate),
    DATENAME(MONTH, FullDate)
FROM DateRange d
WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.DimDate x
    WHERE x.FullDate = d.FullDate
)
OPTION (MAXRECURSION 0);



--creat the fact salses table
IF NOT EXISTS
(SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'FactSales')
BEGIN
    CREATE TABLE gold.FactSales
    (
        SalesKey INT IDENTITY(1,1) PRIMARY KEY,

        Row_ID INT NOT NULL,
        Order_ID VARCHAR(50) NOT NULL,

        CustomerKey INT NOT NULL,
        ProductKey INT NOT NULL,
        OrderDateKey INT NOT NULL,
        ShipDateKey INT NOT NULL,
        LocationKey INT NOT NULL,
        ShippingKey INT NOT NULL,

        Sales DECIMAL(18,4),
        Quantity INT,
        Discount DECIMAL(5,4),
        Profit DECIMAL(18,4),

        CONSTRAINT UQ_FactSales_RowID UNIQUE (Row_ID),

        CONSTRAINT FK_FactSales_Customer
            FOREIGN KEY (CustomerKey)
            REFERENCES gold.DimCustomer(CustomerKey),

        CONSTRAINT FK_FactSales_Product
            FOREIGN KEY (ProductKey)
            REFERENCES gold.DimProduct(ProductKey),

        CONSTRAINT FK_FactSales_OrderDate
            FOREIGN KEY (OrderDateKey)
            REFERENCES gold.DimDate(DateKey),

        CONSTRAINT FK_FactSales_ShipDate
            FOREIGN KEY (ShipDateKey)
            REFERENCES gold.DimDate(DateKey),

        CONSTRAINT FK_FactSales_Location
            FOREIGN KEY (LocationKey)
            REFERENCES gold.DimLocation(LocationKey),

        CONSTRAINT FK_FactSales_Shipping
            FOREIGN KEY (ShippingKey)
            REFERENCES gold.DimShipping(ShippingKey)
    );
END;
GO


--load data into fact salses table

INSERT INTO gold.FactSales
(
    Row_ID,
    Order_ID,
    CustomerKey,
    ProductKey,
    OrderDateKey,
    ShipDateKey,
    LocationKey,
    ShippingKey,
    Sales,
    Quantity,
    Discount,
    Profit
)
SELECT
    s.Row_ID,
    s.Order_ID,

    c.CustomerKey,
    p.ProductKey,
    od.DateKey,
    sd.DateKey,
    l.LocationKey,
    sh.ShippingKey,

    s.Sales,
    s.Quantity,
    s.Discount,
    s.Profit

FROM silver.CentralSuperstore s

JOIN gold.DimCustomer c
    ON s.Customer_ID = c.Customer_ID

JOIN gold.DimProduct p
    ON s.Product_ID = p.Product_ID
   AND s.Product_Name = p.Product_Name
   AND s.Category = p.Category
   AND s.Sub_Category = p.Sub_Category

JOIN gold.DimDate od
    ON s.Order_Date = od.FullDate

JOIN gold.DimDate sd
    ON s.Ship_Date = sd.FullDate

JOIN gold.DimLocation l
    ON s.Country = l.Country
   AND s.City = l.City
   AND s.State = l.State
   AND s.Postal_Code = l.PostalCode
   AND s.Region = l.Region

JOIN gold.DimShipping sh
    ON s.Ship_Mode = sh.Ship_Mode  
   WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.FactSales f
    WHERE f.Row_ID = s.Row_ID
);
GO

---------------------------------------------------------------------
--data validation
-- Check total rows
SELECT COUNT(*) AS TotalRows
FROM staging.stg_CentralSuperstore;


-- View the staging data
SELECT *
FROM staging.stg_CentralSuperstore;


-- Check duplicates
SELECT
    Row_ID,
    COUNT(*) AS DuplicateCount
FROM staging.stg_CentralSuperstore
GROUP BY Row_ID
HAVING COUNT(*) > 1;


-- Check the main categorical values
SELECT DISTINCT Segment
FROM staging.stg_CentralSuperstore
ORDER BY Segment;

SELECT DISTINCT Ship_Mode
FROM staging.stg_CentralSuperstore
ORDER BY Ship_Mode;

SELECT DISTINCT Category
FROM staging.stg_CentralSuperstore
ORDER BY Category;

SELECT DISTINCT Sub_Category
FROM staging.stg_CentralSuperstore
ORDER BY Sub_Category;

SELECT DISTINCT Region
FROM staging.stg_CentralSuperstore
ORDER BY Region;


-- Check date range
SELECT
    MIN(TRY_CONVERT(DATE, Order_Date, 103)) AS FirstOrderDate,
    MAX(TRY_CONVERT(DATE, Order_Date, 103)) AS LastOrderDate,
    MIN(TRY_CONVERT(DATE, Ship_Date, 103)) AS FirstShipDate,
    MAX(TRY_CONVERT(DATE, Ship_Date, 103)) AS LastShipDate
FROM staging.stg_CentralSuperstore;


-- Check Product ID consistency
SELECT
    Product_ID,
    COUNT(DISTINCT Product_Name) AS ProductNameCount,
    COUNT(DISTINCT Category) AS CategoryCount,
    COUNT(DISTINCT Sub_Category) AS SubCategoryCount
FROM staging.stg_CentralSuperstore
GROUP BY Product_ID
HAVING
    COUNT(DISTINCT Product_Name) > 1
    OR COUNT(DISTINCT Category) > 1
    OR COUNT(DISTINCT Sub_Category) > 1;


-- Show the products with inconsistent information
SELECT
    Product_ID,
    Product_Name,
    Category,
    Sub_Category
FROM staging.stg_CentralSuperstore
WHERE Product_ID IN
(
    SELECT Product_ID
    FROM staging.stg_CentralSuperstore
    GROUP BY Product_ID
    HAVING
        COUNT(DISTINCT Product_Name) > 1
        OR COUNT(DISTINCT Category) > 1
        OR COUNT(DISTINCT Sub_Category) > 1
)
ORDER BY Product_ID, Product_Name;


-- Check a specific product
SELECT *
FROM staging.stg_CentralSuperstore
WHERE Product_ID = 'FUR-CH-10001146'
ORDER BY Product_Name;


-- Check customer data
SELECT
    Customer_ID,
    COUNT(DISTINCT Customer_Name) AS CustomerNameCount,
    COUNT(DISTINCT Segment) AS SegmentCount
FROM staging.stg_CentralSuperstore
GROUP BY Customer_ID
HAVING
    COUNT(DISTINCT Customer_Name) > 1
    OR COUNT(DISTINCT Segment) > 1;


-- Check location data
SELECT
    Postal_Code,
    COUNT(DISTINCT City) AS CityCount,
    COUNT(DISTINCT State) AS StateCount,
    COUNT(DISTINCT Region) AS RegionCount
FROM staging.stg_CentralSuperstore
GROUP BY Postal_Code
HAVING
    COUNT(DISTINCT City) > 1
    OR COUNT(DISTINCT State) > 1
    OR COUNT(DISTINCT Region) > 1;


-- Check for invalid dates
SELECT
    COUNT(*) AS InvalidDateRows
FROM staging.stg_CentralSuperstore
WHERE
    TRY_CONVERT(DATE, Order_Date, 103)
    >
    TRY_CONVERT(DATE, Ship_Date, 103);

-- BUSINESS ANALYTICS
-- Query 1: Business KPIs
SELECT
    SUM(Sales) AS TotalSales,
    SUM(Profit) AS TotalProfit,
    SUM(Quantity) AS TotalQuantity
FROM gold.FactSales;


-- Query 2: Sales and Profit by Customer
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
-- BEFORE adding index:
--   Table 'FactSales'.    Scan count 1, logical reads 27
--   Table 'DimCustomer'.  Scan count 1, logical reads 6
--   CPU time = 0 ms, elapsed time = 73 ms

WITH CustomerSales AS
(
    SELECT
        f.CustomerKey,
        SUM(f.Sales) AS TotalSales,
        SUM(f.Profit) AS TotalProfit
    FROM gold.FactSales f
    GROUP BY f.CustomerKey
)
SELECT
    c.Customer_Name,
    cs.TotalSales,
    cs.TotalProfit
FROM CustomerSales cs
JOIN gold.DimCustomer c
    ON cs.CustomerKey = c.CustomerKey
ORDER BY cs.TotalSales DESC;

-- Optimization test: create an index for Query 2
CREATE NONCLUSTERED INDEX IX_FactSales_CustomerKey
ON gold.FactSales(CustomerKey)
INCLUDE (Sales, Profit);
GO
-- AFTER adding index:
--   Table 'FactSales'.    Scan count 1, logical reads 12
--   Table 'DimCustomer'.  Scan count 1, logical reads 6
--   CPU time = 0 ms, elapsed time = 58 ms

-- RESULT:
--   FactSales logical reads decreased from 27 to 12,
--   which is about a 56% reduction.
--   Elapsed time also decreased from 73 ms to 58 ms.
--
--   The index was created on CustomerKey because the query
--   groups FactSales by CustomerKey. Sales and Profit were
--   included because they are used in the SUM calculations.
--
--   The improvement is relatively small in actual time because
--   the current dataset contains only 2,323 rows. However,
--   the reduction in logical reads shows that the index improves
--   how SQL Server accesses FactSales for this query.
--
--   With a much larger dataset, this type of index can provide
--   a more noticeable performance benefit by reducing the amount
--   of data SQL Server needs to read.

-- Query 3: Sales and Profit by Category
SELECT
    p.Category,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimProduct p
    ON f.ProductKey = p.ProductKey
GROUP BY p.Category
ORDER BY TotalSales DESC;


-- Query 4: Profit by Segment
SELECT
    c.Segment,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimCustomer c
    ON f.CustomerKey = c.CustomerKey
GROUP BY c.Segment
ORDER BY TotalSales DESC;


-- Query 5: Monthly Sales Trend
SELECT
    d.Year,
    d.Month,
    d.MonthName,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimDate d
    ON f.OrderDateKey = d.DateKey
GROUP BY
    d.Year,
    d.Month,
    d.MonthName
ORDER BY
    d.Year,
    d.Month;


-- Query 6: Sales and Profit by Sub-Category
SELECT
    p.Sub_Category,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimProduct p
    ON f.ProductKey = p.ProductKey
GROUP BY p.Sub_Category
ORDER BY TotalProfit ASC;


-- Query 7: Which products are actually losing money?
SELECT TOP 10
    p.Product_Name,
    p.Category,
    p.Sub_Category,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimProduct p
    ON f.ProductKey = p.ProductKey
GROUP BY
    p.Product_Name,
    p.Category,
    p.Sub_Category
HAVING SUM(f.Profit) < 0
ORDER BY TotalProfit ASC;


-- Query 8: Does discount affect profit?
SELECT
    f.Discount,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
GROUP BY f.Discount
ORDER BY f.Discount;


-- Query 9: Average Profit Margin by Category
SELECT
    p.Category,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit,
    SUM(f.Profit) / NULLIF(SUM(f.Sales), 0) * 100 AS ProfitMargin
FROM gold.FactSales f
JOIN gold.DimProduct p
    ON f.ProductKey = p.ProductKey
GROUP BY p.Category
ORDER BY ProfitMargin DESC;


-- Query 10: Sales and Profit by Year
SELECT
    d.Year,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimDate d
    ON f.OrderDateKey = d.DateKey
GROUP BY d.Year
ORDER BY d.Year;


-- Query 11: Yearly Profit Margin
SELECT
    d.Year,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit,
    SUM(f.Profit) / NULLIF(SUM(f.Sales), 0) * 100 AS ProfitMargin
FROM gold.FactSales f
JOIN gold.DimDate d
    ON f.OrderDateKey = d.DateKey
GROUP BY d.Year
ORDER BY d.Year;


-- Query 12: Discount by Year
SELECT
    d.Year,
    f.Discount,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimDate d
    ON f.OrderDateKey = d.DateKey
GROUP BY
    d.Year,
    f.Discount
ORDER BY
    d.Year,
    f.Discount;

-- Query 13: Customer Profitability
SELECT
    c.Customer_Name,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit
FROM gold.FactSales f
JOIN gold.DimCustomer c
    ON f.CustomerKey = c.CustomerKey
GROUP BY c.Customer_Name
HAVING
    SUM(f.Sales) > 5000
    AND SUM(f.Profit) < 0
ORDER BY TotalProfit ASC;


-- Query 14: Discount Classification
SELECT
    f.Discount,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit,
    CASE
        WHEN f.Discount = 0 THEN 'No Discount'
        WHEN f.Discount <= 0.20 THEN 'Low Discount'
        WHEN f.Discount <= 0.40 THEN 'Medium Discount'
        ELSE 'High Discount'
    END AS DiscountCategory
FROM gold.FactSales f
GROUP BY
    f.Discount
ORDER BY f.Discount;


-- Query 15: Top Customers by Profit Margin
SELECT TOP 10
    c.Customer_Name,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit,
    SUM(f.Profit) / NULLIF(SUM(f.Sales), 0) * 100 AS ProfitMargin
FROM gold.FactSales f
JOIN gold.DimCustomer c
    ON f.CustomerKey = c.CustomerKey
GROUP BY c.Customer_Name
HAVING SUM(f.Sales) > 1000
ORDER BY ProfitMargin DESC;
GO
-- Query Optimization
-- Execution plan was reviewed for this query.
-- SQL Server uses clustered index scans and a hash join.
-- The current dataset is small (2,323 rows), so the query runs very quickly.
-- No additional index was added because there was no clear performance need.
-- VIEW: Sales Performance

CREATE VIEW gold.vw_SalesPerformance
AS
SELECT
    f.Row_ID,
    f.Order_ID,

    c.Customer_ID,
    c.Customer_Name,
    c.Segment,

    p.Product_ID,
    p.Product_Name,
    p.Category,
    p.Sub_Category,

    d.FullDate AS OrderDate,
    d.Year,
    d.Month,
    d.MonthName,

    l.Country,
    l.City,
    l.State,
    l.PostalCode,
    l.Region,

    sh.Ship_Mode,

    f.Sales,
    f.Quantity,
    f.Discount,
    f.Profit

FROM gold.FactSales f

JOIN gold.DimCustomer c
    ON f.CustomerKey = c.CustomerKey

JOIN gold.DimProduct p
    ON f.ProductKey = p.ProductKey

JOIN gold.DimDate d
    ON f.OrderDateKey = d.DateKey

JOIN gold.DimLocation l
    ON f.LocationKey = l.LocationKey

JOIN gold.DimShipping sh
    ON f.ShippingKey = sh.ShippingKey;
GO
SELECT TOP 10 *
FROM gold.vw_SalesPerformance;


--view 2 KPI summary by category showing total sales, profit, and profit margin
CREATE VIEW gold.vw_CategoryKPI
AS
SELECT
    p.Category,
    SUM(f.Sales) AS TotalSales,
    SUM(f.Profit) AS TotalProfit,
    SUM(f.Profit) / NULLIF(SUM(f.Sales), 0) * 100 AS ProfitMargin
FROM gold.FactSales f
JOIN gold.DimProduct p
    ON f.ProductKey = p.ProductKey
GROUP BY
    p.Category;
GO

--test
SELECT *
FROM gold.vw_CategoryKPI
ORDER BY ProfitMargin DESC;


-- PROCEDURE
GO

CREATE OR ALTER PROCEDURE gold.usp_SalesKPI
    @Year INT = NULL,
    @Category VARCHAR(50) =NULL
AS
BEGIN

    SELECT
        SUM(f.Sales) AS TotalSales,
        SUM(f.Profit) AS TotalProfit,
        SUM(f.Quantity) AS TotalQuantity,

        SUM(f.Profit) / NULLIF(SUM(f.Sales), 0) * 100
            AS ProfitMargin

    FROM gold.FactSales f
    JOIN gold.DimDate d
        ON f.OrderDateKey = d.DateKey
    JOIN gold.DimProduct p
        ON f.ProductKey = p.ProductKey
   WHERE (@Year IS NULL OR d.Year = @Year)
      AND (@Category IS NULL OR p.Category = @Category);
END;
GO
--test the PROCEDURE
EXEC gold.usp_SalesKPI 
       @Year = 2016,
       @Category = 'Technology';
EXEC gold.usp_SalesKPI 
       @Year = 2016;
EXEC gold.usp_SalesKPI
       @Category = 'Technology';
EXEC gold.usp_SalesKPI;