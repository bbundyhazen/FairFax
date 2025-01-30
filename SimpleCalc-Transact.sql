-- Step 1: Create a temporary table to store the intermediate CTE result
CREATE TABLE #IntermediateData (
    CalculationTag NVARCHAR(255),
    CalculationType NVARCHAR(10),
    Value FLOAT,
    Tag NVARCHAR(255)
);

-- Step 2: Execute CTEs and store the result in #IntermediateData
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
    SELECT pp.CalculationTag, pp.Tag, d.Value
    FROM ParsedParameters pp
    INNER JOIN [dbo].[Data] d ON pp.Tag = d.Tag
    WHERE d.DateTime = '2024-01-01'
)
INSERT INTO #IntermediateData (CalculationTag, CalculationType, Value, Tag)
SELECT rd.CalculationTag, sc.CalculationType, rd.Value, rd.Tag
FROM RetrievedData rd
INNER JOIN StandardCalculations sc ON rd.CalculationTag = sc.Tag;

-- Step 3: Create another temporary table for results
CREATE TABLE #Results (
    CalculationTag NVARCHAR(255),
    CalculatedValue FLOAT
);

-- Step 4: Declare variables for calculations
DECLARE @CalculationTag NVARCHAR(255);
DECLARE @CalculationType NVARCHAR(10);
DECLARE @Sum FLOAT;
DECLARE @Difference FLOAT;
DECLARE @Product FLOAT;
DECLARE @Numerator FLOAT;
DECLARE @Denominator FLOAT;
DECLARE @NegativeCount INT;

DECLARE CalculationCursor CURSOR FOR
SELECT DISTINCT CalculationTag, CalculationType FROM #IntermediateData;

OPEN CalculationCursor;
FETCH NEXT FROM CalculationCursor INTO @CalculationTag, @CalculationType;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Reset variables
    SET @Sum = 0;
    SET @Difference = NULL;
    SET @Product = 1;
    SET @Numerator = NULL;
    SET @Denominator = 1;
    SET @NegativeCount = 0;

    -- Addition Handling
    IF @CalculationType = '+'
    BEGIN
        IF @CalculationTag LIKE '%ADD.NULLS%'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value IS NULL)
                INSERT INTO #Results VALUES (@CalculationTag, NULL)
            ELSE
            BEGIN
                SELECT @Sum += ISNULL(Value, 0) 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag;
                INSERT INTO #Results VALUES (@CalculationTag, @Sum);
            END
        END
        ELSE IF @CalculationTag LIKE '%ADD.NOTNULLS%'
        BEGIN
            SELECT @Sum += ISNULL(Value, 0) 
            FROM #IntermediateData 
            WHERE CalculationTag = @CalculationTag;
            INSERT INTO #Results VALUES (@CalculationTag, @Sum);
        END
    END

    -- Subtraction Handling
    ELSE IF @CalculationType = '-'
    BEGIN
        IF @CalculationTag LIKE '%SUBTRACT.NULLS%'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value IS NULL)
                INSERT INTO #Results VALUES (@CalculationTag, NULL)
            ELSE
            BEGIN
                SELECT TOP 1 @Difference = Value 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                ORDER BY Tag ASC;
                SELECT @Difference -= ISNULL(Value, 0)
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                AND Tag <> (SELECT TOP 1 Tag FROM #IntermediateData WHERE CalculationTag = @CalculationTag ORDER BY Tag ASC);
                INSERT INTO #Results VALUES (@CalculationTag, @Difference);
            END
        END
        ELSE IF @CalculationTag LIKE '%SUBTRACT.NOTNULLS%'
        BEGIN
            SELECT TOP 1 @Difference = Value 
            FROM #IntermediateData 
            WHERE CalculationTag = @CalculationTag 
            ORDER BY Tag ASC;
            SELECT @Difference -= ISNULL(Value, 0)
            FROM #IntermediateData 
            WHERE CalculationTag = @CalculationTag 
            AND Tag <> (SELECT TOP 1 Tag FROM #IntermediateData WHERE CalculationTag = @CalculationTag ORDER BY Tag ASC);
            INSERT INTO #Results VALUES (@CalculationTag, @Difference);
        END
    END

    -- Multiplication Handling
    ELSE IF @CalculationType = '*'
    BEGIN
        IF @CalculationTag LIKE '%MULTIPLY.NULLS%'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value IS NULL)
                INSERT INTO #Results VALUES (@CalculationTag, NULL)
            ELSE
            BEGIN
                SELECT @Product *= ISNULL(Value, 1) 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag;
                INSERT INTO #Results VALUES (@CalculationTag, @Product);
            END
        END
        ELSE IF @CalculationTag LIKE '%MULTIPLY.ZEROES%'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value = 0)
                INSERT INTO #Results VALUES (@CalculationTag, 0)
            ELSE
            BEGIN
                SELECT @Product *= ISNULL(Value, 1) 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag;
                INSERT INTO #Results VALUES (@CalculationTag, @Product);
            END
        END
        ELSE IF @CalculationTag LIKE '%MULTIPLY.NONZEROES%'
        BEGIN
            SELECT @Product *= ISNULL(Value, 1) 
            FROM #IntermediateData 
            WHERE CalculationTag = @CalculationTag;
            INSERT INTO #Results VALUES (@CalculationTag, @Product);
        END
    END

    -- Division Handling
    ELSE IF @CalculationType = '/'
    BEGIN
        IF @CalculationTag LIKE '%DIVIDE.NULLS%'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value IS NULL)
                INSERT INTO #Results VALUES (@CalculationTag, NULL)
            ELSE
            BEGIN
                SELECT TOP 1 @Numerator = Value 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                ORDER BY Tag ASC;
                SELECT @Denominator *= ISNULL(Value, 1) 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                AND Tag <> (SELECT TOP 1 Tag FROM #IntermediateData WHERE CalculationTag = @CalculationTag ORDER BY Tag ASC);
                INSERT INTO #Results VALUES (@CalculationTag, @Numerator / NULLIF(@Denominator, 0));
            END
        END
        ELSE IF @CalculationTag LIKE '%DIVIDE.UNDEFINED.NULLS%'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND (Value IS NULL OR Value = 0))
                INSERT INTO #Results VALUES (@CalculationTag, NULL)
            ELSE
            BEGIN
                SELECT TOP 1 @Numerator = Value 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                ORDER BY Tag ASC;
                SELECT @Denominator *= ISNULL(Value, 1) 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                AND Tag <> (SELECT TOP 1 Tag FROM #IntermediateData WHERE CalculationTag = @CalculationTag ORDER BY Tag ASC);
                INSERT INTO #Results VALUES (@CalculationTag, @Numerator / NULLIF(@Denominator, 0));
            END
        END
        ELSE IF @CalculationTag LIKE '%DIVIDE.CHAINED.ZEROES%'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value = 0)
                INSERT INTO #Results VALUES (@CalculationTag, 0)
            ELSE
            BEGIN
                SELECT TOP 1 @Numerator = Value 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                ORDER BY Tag ASC;
                SELECT @Denominator *= ISNULL(Value, 1) 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag 
                AND Tag <> (SELECT TOP 1 Tag FROM #IntermediateData WHERE CalculationTag = @CalculationTag ORDER BY Tag ASC);
                INSERT INTO #Results VALUES (@CalculationTag, @Numerator / NULLIF(@Denominator, 0));
            END
        END
    END

    FETCH NEXT FROM CalculationCursor INTO @CalculationTag, @CalculationType;
END

CLOSE CalculationCursor;
DEALLOCATE CalculationCursor;

-- Return the calculated results
SELECT * FROM #Results;

-- Clean up
DROP TABLE #IntermediateData;
DROP TABLE #Results;
