CREATE PROCEDURE UpdateCalcData
AS
BEGIN
    SET NOCOUNT ON;

    -- Temporary table to store intermediate data
    CREATE TABLE #IntermediateData (
        CalculationTag NVARCHAR(255),
        CalculationType NVARCHAR(10),
        Value FLOAT,
        DateTime DATETIME,
        RowNum INT
    );

    -- Parse calculation parameters and join with data
    WITH StandardCalculations AS (
        SELECT [Tag], [Calculation Type] AS CalculationType, [Calculation Parameters Tag] AS Parameters
        FROM [dbo].[Tags]
        WHERE [Tag Class] = 'Calc'
            AND [Custom Calculation] IS NULL
    ),
    ParsedParameters AS (
        SELECT sc.Tag AS CalculationTag, TRIM(value) AS Tag
        FROM StandardCalculations sc
        CROSS APPLY STRING_SPLIT(sc.Parameters, ',')
    ),
    RetrievedData AS (
        SELECT pp.CalculationTag, sc.CalculationType, d.Value, d.DateTime,
               ROW_NUMBER() OVER (PARTITION BY pp.CalculationTag, d.DateTime ORDER BY pp.Tag ASC) AS RowNum
        FROM ParsedParameters pp
        INNER JOIN [dbo].[Data] d ON pp.Tag = d.Tag
        INNER JOIN StandardCalculations sc ON pp.CalculationTag = sc.Tag
    )
    INSERT INTO #IntermediateData (CalculationTag, CalculationType, Value, DateTime, RowNum)
    SELECT CalculationTag, CalculationType, Value, DateTime, RowNum
    FROM RetrievedData;

    -- Perform calculations using set-based operations with proper NULL and zero handling
    INSERT INTO CalcData (Tag, DateTime, Value)
    SELECT CalculationTag, DateTime,
        CASE 
            -- Addition: NULL if any value is NULL, otherwise sum
            WHEN CalculationType = '+' 
                THEN CASE WHEN COUNT(CASE WHEN Value IS NULL THEN 1 END) > 0 THEN NULL ELSE SUM(Value) END
            
            -- Subtraction: NULL if any value is NULL, start with first value and subtract the rest
            WHEN CalculationType = '-' 
                THEN CASE WHEN COUNT(CASE WHEN Value IS NULL THEN 1 END) > 0 THEN NULL 
                          ELSE MAX(CASE WHEN RowNum = 1 THEN Value END) - SUM(CASE WHEN RowNum > 1 THEN Value ELSE 0 END)
                     END
            
            -- Multiplication: NULL if any value is NULL, 0 if any value is 0, otherwise product
            WHEN CalculationType = '*' 
                THEN CASE WHEN COUNT(CASE WHEN Value IS NULL THEN 1 END) > 0 THEN NULL 
                          WHEN COUNT(CASE WHEN Value = 0 THEN 1 END) > 0 THEN 0 
                          ELSE EXP(SUM(LOG(NULLIF(Value, 0)))) 
                     END
            
            -- Division: NULL if any value is NULL or denominator is 0, otherwise divide
            WHEN CalculationType = '/' 
                THEN CASE 
                        WHEN COUNT(CASE WHEN Value IS NULL OR Value = 0 THEN 1 END) > 0 THEN NULL 
                        ELSE MAX(CASE WHEN RowNum = 1 THEN Value END) / EXP(SUM(CASE WHEN RowNum > 1 THEN LOG(NULLIF(Value, 0)) ELSE 0 END)) 
                     END
        END AS CalculatedValue
    FROM #IntermediateData
    GROUP BY CalculationTag, CalculationType, DateTime;

    -- Cleanup
    DROP TABLE #IntermediateData;
END;