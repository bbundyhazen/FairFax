CREATE PROCEDURE CustomCalculation
AS
BEGIN
    SET NOCOUNT ON;

    -- Temporary table to store intermediate data
    CREATE TABLE #IntermediateData (
        CalculationTag NVARCHAR(255),
        CalculationType NVARCHAR(30),
        Value FLOAT,
        Tag NVARCHAR(255),
        DateTime DATETIME
    );

    -- Parse calculation parameters and join with data
    WITH CustomCalculations AS (
        SELECT [Tag], [Calculation Type] AS CalculationType, [Calculation Parameters Tag] AS Parameters, [Custom Calculation] AS Expression
        FROM [dbo].[Tags]
        WHERE [Tag Class] = 'Calc'
            AND [Calculation Type] = 'Custom'
    ),
    ParsedParameters AS (
        SELECT 
            cc.Tag AS CalculationTag, 
            TRIM(value) AS Tag
        FROM CustomCalculations cc
        CROSS APPLY STRING_SPLIT(cc.Parameters, ',')
    ),
    RetrievedData AS (
        SELECT 
            pp.CalculationTag, 
            pp.Tag, 
            d.Value, 
            CAST(d.DateTime AS DATE) AS DateTime
        FROM ParsedParameters pp
        INNER JOIN [dbo].[Data] d 
            ON pp.Tag = d.Tag
    ),
    -- Generate unique CalculationTag and DateTime pairs
    CalcDates AS (
        SELECT DISTINCT CalculationTag, DateTime
        FROM RetrievedData
    ),
    -- Ensure missing dates are handled correctly
    ExpandedData AS (
        SELECT
            rd.CalculationTag,
            rd.Tag,
            CASE 
                WHEN rd.DateTime <> d.DateTime THEN NULL 
                ELSE rd.Value 
            END AS Value,
            d.DateTime
        FROM RetrievedData rd
        INNER JOIN CalcDates d ON rd.CalculationTag = d.CalculationTag
    ),
        RankedData AS (
        SELECT
            CalculationTag,
            Tag,
            Value,
            DateTime,
            ROW_NUMBER() OVER (PARTITION BY CalculationTag, Tag, DateTime ORDER BY Value DESC) AS Valid
        FROM ExpandedData
    ),
    FinalData as (
        SELECT  
            rd.CalculationTag, 
            rd.Value,
            rd.Tag, 
            rd.DateTime
        FROM RankedData rd
        WHERE Valid = 1
    ),
    -- Prepare data for substitution
    SubstitutedValues AS (
        SELECT 
            cc.CalculationTag,
            cc.CalculationType,
            cc.Expression,
            STRING_AGG(CONCAT(fd.Tag, '=', fd.Value), ',') AS Substitutions,
            fd.DateTime
        FROM CustomCalculations cc
        INNER JOIN FinalData fd ON cc.Tag = fd.CalculationTag
        GROUP BY cc.CalculationTag, cc.CalculationType, cc.Expression, fd.DateTime
    )
    INSERT INTO #IntermediateData (CalculationTag, CalculationType, Value, Tag, DateTime)
    SELECT 
        sv.CalculationTag,
        sv.CalculationType,
        dbo.EvaluateExpression(sv.Expression, sv.Substitutions),
        sv.CalculationTag,
        sv.DateTime
    FROM SubstitutedValues sv;

    -- Final result selection
    SELECT * FROM #IntermediateData;
    DROP TABLE #IntermediateData;
END









    -- Step 1: Retrieve the raw expressions

    WITH CustomCalculations AS (

        SELECT 

            t.Tag AS CalculationTag, 

            t.[Calculation Type] AS CalculationType, 

            t.[Custom Calculation] AS Expression

        FROM [dbo].[Tags] t

        WHERE t.[Tag Class] = 'Calc' 

          AND t.[Calculation Type] = 'Custom'

    ),
 
    -- Step 2: Extract parameters and their values

    ParsedParameters AS (

        SELECT 

            cc.CalculationTag, 

            TRIM(value) AS ParameterTag

        FROM CustomCalculations cc

        CROSS APPLY STRING_SPLIT(cc.Expression, ' ')

    ),
 
    RetrievedData AS (

        SELECT 

            pp.CalculationTag, 

            pp.ParameterTag, 

            d.Value,

            CAST(d.DateTime AS DATE) AS DateTime

        FROM ParsedParameters pp

        INNER JOIN [dbo].[Data] d 

            ON pp.ParameterTag = d.Tag

    ),
 
    -- Step 3: Replace variable names with actual values

    SubstitutedExpressions AS (

        SELECT 

            cc.CalculationTag,

            cc.CalculationType,

            cc.Expression AS OriginalExpression,

            rd.DateTime,

            -- Replace variable names with actual values in SQL

            REPLACE(

                cc.Expression, rd.ParameterTag, CAST(rd.Value AS NVARCHAR(MAX))

            ) AS EvaluatableExpression

        FROM CustomCalculations cc

        INNER JOIN RetrievedData rd ON cc.CalculationTag = rd.CalculationTag

    )
	Select * from SubstitutedExpressions;
    --SELECT 
    --    se.CalculationTag,
    --    se.CalculationType,
    --    se.EvaluatableExpression,
    --    CAST((EXEC sp_executesql N'SELECT ' + se.EvaluatableExpression) AS FLOAT), -- Evaluates the math expression
    --    se.DateTime
    --FROM SubstitutedExpressions se;
 
    ---- Step 5: Store final results

    --SELECT * FROM #IntermediateData;
 
    ---- Cleanup temp table

    --DROP TABLE #IntermediateData;

 
