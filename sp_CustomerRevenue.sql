CREATE PROCEDURE sp_CalculateCustomerRevenue
    @FromYear INT = NULL,
    @ToYear INT = NULL,
    @Period VARCHAR(10) = 'Year',
    @CustomerKey INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Step 1: Declare and set the default values for the input parameters
        IF @FromYear IS NULL
            SET @FromYear = (SELECT MIN(YEAR([Order Date Key])) FROM Fact.[Order]);

        IF @ToYear IS NULL
            SET @ToYear = (SELECT MAX(YEAR([Order Date Key])) FROM Fact.[Order]);

        -- Step 2: Declare the table name based on input parameters
        DECLARE @TableName NVARCHAR(255);
        SET @TableName = ISNULL(CAST(@CustomerKey AS NVARCHAR(10)), 'All') + '_' +
                         ISNULL((SELECT Customer FROM Dimension.Customer WHERE [Customer Key] = @CustomerKey), 'All') + '_' +
                         CAST(@FromYear AS NVARCHAR(4)) + '_' + 
                         (CASE WHEN @FromYear = @ToYear THEN '' ELSE CAST(@ToYear AS NVARCHAR(4)) END) + '_' +
                         LEFT(@Period, 1);

        -- Step 3: Check if the table exists, if it does drop it
        IF OBJECT_ID('[' + @TableName + ']', 'U') IS NOT NULL
            EXEC('DROP TABLE [' + @TableName + ']');

        -- Step 4: Based on the period input, generate the SQL to create and insert data
        DECLARE @SQL NVARCHAR(MAX);

        SET @SQL = 'CREATE TABLE [' + @TableName + '] ([Customer Key] INT, Customer VARCHAR(50), [Period] VARCHAR(8), [Revenue] NUMERIC(19,2));';

        SET @SQL = @SQL + ' INSERT INTO [' + @TableName + '] 
                           SELECT 
                               dc.[Customer Key],
                               dc.Customer,';

        IF @Period IN ('Month', 'M')
            SET @SQL = @SQL + ' DATENAME(MONTH, fo.[Order Date Key]) + '' '' + CAST(YEAR(fo.[Order Date Key]) AS VARCHAR(4)) AS [Period],';
        ELSE IF @Period IN ('Quarter', 'Q')
            SET @SQL = @SQL + ' ''Q'' + DATENAME(QUARTER, fo.[Order Date Key]) + '' '' + CAST(YEAR(fo.[Order Date Key]) AS VARCHAR(4)) AS [Period],';
        ELSE 
            SET @SQL = @SQL + ' CAST(YEAR(fo.[Order Date Key]) AS VARCHAR(4)) AS [Period],';

        SET @SQL = @SQL + ' SUM(fo.Quantity * fo.[Unit Price]) AS Revenue
                           FROM Fact.[Order] fo
                           JOIN Dimension.Customer dc ON fo.[Customer Key] = dc.[Customer Key]
                           WHERE YEAR(fo.[Order Date Key]) BETWEEN @FromYear AND @ToYear' +
                           (CASE WHEN @CustomerKey IS NOT NULL THEN ' AND dc.[Customer Key] = @CustomerKey' ELSE '' END) +
                           ' GROUP BY dc.[Customer Key], dc.Customer';

        IF @Period IN ('Month', 'M')
            SET @SQL = @SQL + ', MONTH(fo.[Order Date Key]), YEAR(fo.[Order Date Key])';
        ELSE IF @Period IN ('Quarter', 'Q')
            SET @SQL = @SQL + ', DATENAME(QUARTER, fo.[Order Date Key]), YEAR(fo.[Order Date Key])';
        ELSE 
            SET @SQL = @SQL + ', YEAR(fo.[Order Date Key])';

        EXEC sp_executesql @SQL, N'@FromYear INT, @ToYear INT, @CustomerKey INT', @FromYear, @ToYear, @CustomerKey;

    END TRY

    BEGIN CATCH
        IF OBJECT_ID('[ErrorLog]', 'U') IS NULL
        BEGIN
            CREATE TABLE [ErrorLog]
            (
                [ErrorID] INT PRIMARY KEY IDENTITY,
                [ErrorNumber] INT,
                [ErrorSeverity] INT,
                [ErrorMessage] VARCHAR(255),
                [Customer Key] INT,
                [Period] VARCHAR(8),
                [CreatedAt] DATETIME DEFAULT GETDATE()
            );
        END

        INSERT INTO [ErrorLog] ([ErrorNumber], [ErrorSeverity], [ErrorMessage], [Customer Key], [Period])
        VALUES (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_MESSAGE(), @CustomerKey, LEFT(@Period, 1));

    END CATCH
END;
