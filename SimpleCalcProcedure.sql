---- With Dates 
--- If not record for the date, then make sure a null value is added for that date and field
--- sum, difference, product (ignore nulls when this is chosen as the type)
    --- build test cases. also some with missing dates)
CREATE PROCEDURE SimpleCalculation
AS
BEGIN
    SET NOCOUNT ON;

    -- Temporary table to store intermediate data
	CREATE TABLE #IntermediateData (
		CalculationTag NVARCHAR(255),
		CalculationType NVARCHAR(30),
		Value FLOAT,
		Tag NVARCHAR(255),
		DateTime DATETIME,
		ParameterOrder INT
	);

    -- Parse calculation parameters and join with data
    WITH StandardCalculations AS (
        SELECT [Tag], [Calculation Type] AS CalculationType, [Calculation Parameters Tag] AS Parameters
        FROM [dbo].[Tags]
        WHERE [Tag Class] = 'Calc'
            AND [Custom Calculation] IS NULL
    ),
    ParsedParameters AS (
        SELECT 
            sc.Tag AS CalculationTag, 
            TRIM(value) AS Tag,
            ROW_NUMBER() OVER (PARTITION BY sc.Tag ORDER BY (SELECT NULL)) AS ParameterOrder
        FROM StandardCalculations sc
        CROSS APPLY STRING_SPLIT(sc.Parameters, ',')
    ),
    RetrievedData AS (
        SELECT 
            pp.CalculationTag, 
            pp.Tag, 
            d.Value, 
            CAST(d.DateTime AS DATE) AS DateTime, 
            pp.ParameterOrder
        FROM ParsedParameters pp
        INNER JOIN [dbo].[Data] d 
            ON pp.Tag = d.Tag
    ),
    -- Generate unique CalculationTag and DateTime pairs
    CalcDates AS (
        SELECT DISTINCT CalculationTag, DateTime
        FROM RetrievedData
    ),
    -- Use INNER JOIN instead of CROSS JOIN to generate expanded data
    ExpandedData AS (
        SELECT
            rd.CalculationTag AS CalculationTag,
            rd.Tag AS Tag,
            CASE 
                WHEN rd.DateTime <> d.DateTime THEN NULL 
                ELSE rd.Value 
            END AS Value,
            d.DateTime AS DateTime,
            rd.ParameterOrder
        FROM RetrievedData rd
            INNER JOIN CalcDates d ON rd.CalculationTag = d.CalculationTag
    ),
    RankedData AS (
        SELECT
            CalculationTag,
            Tag,
            Value,
            DateTime,
            ParameterOrder,
            ROW_NUMBER() OVER (PARTITION BY CalculationTag, Tag, DateTime ORDER BY Value DESC) AS Valid
        FROM ExpandedData
    ),
    FinalData as (
        SELECT  
            rd.CalculationTag, 
			sc.CalculationType,
            rd.Value,
            rd.Tag, 
            rd.DateTime, 
            rd.ParameterOrder
        FROM RankedData rd
                INNER JOIN StandardCalculations sc ON rd.CalculationTag = sc.Tag
        WHERE Valid = 1
    )
    INSERT INTO #IntermediateData (CalculationTag, CalculationType, Value, Tag, DateTime, ParameterOrder)
    SELECT * FROM FinalData;


    -- Table to store results
    CREATE TABLE #Results (
        CalculationTag NVARCHAR(255),
        CalculatedValue FLOAT,
        DateTime DATETIME
    );

    DECLARE @CalculationTag NVARCHAR(255);
    DECLARE @CalculationType NVARCHAR(10);
    DECLARE @CurrentDateTime DATETIME;
    DECLARE @Sum FLOAT;
    DECLARE @Difference FLOAT;
    DECLARE @Product FLOAT;
    DECLARE @Numerator FLOAT;
    DECLARE @Denominator FLOAT;
    DECLARE @HasZeroOrNull BIT;

    DECLARE CalculationCursor CURSOR FOR
    SELECT DISTINCT CalculationTag, CalculationType, DateTime FROM #IntermediateData;

    OPEN CalculationCursor;
    FETCH NEXT FROM CalculationCursor INTO @CalculationTag, @CalculationType, @CurrentDateTime;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Reset variables
        SET @Sum = 0;
        SET @Difference = 0;
        SET @Product = 1;
        SET @Numerator = 0;
        SET @Denominator = 1;
        SET @HasZeroOrNull = 0;

        IF @CalculationType = '+'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value IS NULL AND DateTime = @CurrentDateTime)
                INSERT INTO #Results VALUES (@CalculationTag, NULL, @CurrentDateTime);
            ELSE
            BEGIN
                SELECT @Sum += Value 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag AND DateTime = @CurrentDateTime;
                INSERT INTO #Results VALUES (@CalculationTag, @Sum, @CurrentDateTime);
            END
        END
        ELSE IF @CalculationType = 'Sum'
        BEGIN
            SELECT @Sum += COALESCE(Value, 0)
            FROM #IntermediateData 
            WHERE CalculationTag = @CalculationTag AND DateTime = @CurrentDateTime;
            INSERT INTO #Results VALUES (@CalculationTag, @Sum, @CurrentDateTime);
        END
        ELSE IF @CalculationType = '-'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value IS NULL AND DateTime = @CurrentDateTime)
                INSERT INTO #Results VALUES (@CalculationTag, NULL, @CurrentDateTime);
            ELSE
            BEGIN
				-- Get the first value as the initial Difference
				SELECT TOP 1 @Difference = Value
				FROM #IntermediateData
				WHERE CalculationTag = @CalculationTag AND DateTime = @CurrentDateTime
				ORDER BY ParameterOrder ASC;

				-- finishing rest of the division
				SELECT @Difference -= Value 
				FROM #IntermediateData
				WHERE CalculationTag = @CalculationTag 
				AND DateTime = @CurrentDateTime
				AND ParameterOrder > 1 
				ORDER BY ParameterOrder ASC; 

				-- Store the result
				INSERT INTO #Results VALUES (@CalculationTag, @Difference, @CurrentDateTime);
            END
        END
        ELSE IF @CalculationType = 'Difference'
        BEGIN
            -- Get the first value as the initial Difference
            SELECT TOP 1 @Difference = COALESCE(Value, 0)
            FROM #IntermediateData
            WHERE CalculationTag = @CalculationTag AND DateTime = @CurrentDateTime
            ORDER BY ParameterOrder ASC;

            -- finishing rest of the division
            SELECT @Difference -= COALESCE(Value, 0)
            FROM #IntermediateData
            WHERE CalculationTag = @CalculationTag 
            AND DateTime = @CurrentDateTime
            AND ParameterOrder > 1 
            ORDER BY ParameterOrder ASC; 

            INSERT INTO #Results VALUES (@CalculationTag, @Difference, @CurrentDateTime);
        END
        ELSE IF @CalculationType = '*'
        BEGIN
            IF EXISTS (SELECT 1 FROM #IntermediateData WHERE CalculationTag = @CalculationTag AND Value IS NULL AND DateTime = @CurrentDateTime)
                INSERT INTO #Results VALUES (@CalculationTag, NULL, @CurrentDateTime);
            ELSE
            BEGIN
                SELECT @Product *= Value 
                FROM #IntermediateData 
                WHERE CalculationTag = @CalculationTag AND DateTime = @CurrentDateTime;
                INSERT INTO #Results VALUES (@CalculationTag, @Product, @CurrentDateTime);
            END
        END
        ELSE IF @CalculationType = 'Product'
        BEGIN
            SELECT @Product *= COALESCE(Value, 1)
            FROM #IntermediateData 
            WHERE CalculationTag = @CalculationTag AND DateTime = @CurrentDateTime;
            INSERT INTO #Results VALUES (@CalculationTag, @Product, @CurrentDateTime);
        END
        ELSE IF @CalculationType = '/'
        BEGIN
			-- Get the first value as the numerator
			SELECT TOP 1 @Numerator = Value 
			FROM #IntermediateData 
			WHERE CalculationTag = @CalculationTag AND DateTime = @CurrentDateTime 
			ORDER BY ParameterOrder ASC; -- Ensures the first value is used as the numerator

            -- Check if any denominator value is NULL or 0
			SELECT @HasZeroOrNull = CASE 
				WHEN EXISTS (
					SELECT 1 
					FROM #IntermediateData 
					WHERE CalculationTag = @CalculationTag 
					AND DateTime = @CurrentDateTime 
					AND ParameterOrder > 1  -- Only check denominators
					AND (Value IS NULL OR Value = 0)
				) THEN 1 
				ELSE 0 
			END;

			-- If the numerator is 0, the result is 0
			IF @Numerator = 0 AND @HasZeroOrNull <> 1
				INSERT INTO #Results VALUES (@CalculationTag, 0, @CurrentDateTime);

			-- If any denominator is 0 or NULL, result is NULL (avoid division by zero)
			ELSE IF @HasZeroOrNull = 1
				INSERT INTO #Results VALUES (@CalculationTag, NULL, @CurrentDateTime);
            ELSE
            BEGIN
				-- Multiply all denominator values in the correct order
				SELECT @Denominator *= Value
				FROM #IntermediateData 
				WHERE CalculationTag = @CalculationTag 
				AND DateTime = @CurrentDateTime 
				AND ParameterOrder > 1  -- Ensures only denominators are multiplied
				ORDER BY ParameterOrder ASC; -- Ensures correct order of multiplication

				INSERT INTO #Results VALUES (@CalculationTag, @Numerator / @Denominator, @CurrentDateTime);
            END
        END

        FETCH NEXT FROM CalculationCursor INTO @CalculationTag, @CalculationType, @CurrentDateTime;
    END

    CLOSE CalculationCursor;
    DEALLOCATE CalculationCursor;

    -- Insert results into CalcData table
	INSERT INTO CalcData (Tag, DateTime, Value)
	SELECT CalculationTag, DateTime, CalculatedValue FROM #Results;

    -- Cleanup
    DROP TABLE #IntermediateData;
    DROP TABLE #Results;
END;