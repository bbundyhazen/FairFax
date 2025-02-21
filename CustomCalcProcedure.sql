 WITH CustomCalculations AS (
    SELECT 
        t.Tag AS CalculationTag, 
        t.[Calculation Type] AS CalculationType,
        [Calculation Parameters Tag] AS Parameters,
        REPLACE(t.[Custom Calculation], ' ', '') AS Expression -- Remove spaces
    FROM [dbo].[Tags] t
    WHERE t.[Tag Class] = 'Calc' 
      AND t.[Calculation Type] = 'Custom'
	  AND t.Tag = 'Calc.SIMPLE.ADD.MULTIPLY'
),
    ParsedParameters AS (
        SELECT 
            cc.CalculationTag, 
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
    -- Use INNER JOIN instead of CROSS JOIN to generate expanded data
    ExpandedData AS (
        SELECT
            rd.CalculationTag AS CalculationTag,
            rd.Tag AS Tag,
            CASE 
                WHEN rd.DateTime <> d.DateTime THEN NULL 
                ELSE rd.Value 
            END AS Value,
            d.DateTime AS DateTime
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
        SELECT Distinct 
            rd.Value as TagValue,
			rd.CalculationTag,
            rd.Tag, 
            rd.DateTime
        FROM RankedData rd
        WHERE Valid = 1
    ),
	ReplacedExpressions AS (
		SELECT 
			CalculationTag, 
			CalculationType, 
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Expression, '(', ' ( '), ')', ' ) '), '+', ' + '), '-', ' - '), '*', ' * '), '/', ' / ') AS Expression
		FROM CustomCalculations
	),
	OrderedParsedExpression AS (
		SELECT 
			re.CalculationTag, 
			TRIM(value) AS ParameterTag,
			ROW_NUMBER() OVER (PARTITION BY re.CalculationTag ORDER BY (SELECT NULL)) AS Position
		FROM ReplacedExpressions re
		CROSS APPLY STRING_SPLIT(re.Expression, ' ')
		WHERE value <> ''
	),
	TotalCounts AS (
		SELECT 
			CalculationTag, 
			COUNT(*) AS TotalCount
		FROM OrderedParsedExpression
		GROUP BY CalculationTag
	),
	FilteringDuplicates AS (
		SELECT 
			o.CalculationTag, 
			o.ParameterTag,
			o.Position
		FROM OrderedParsedExpression o
			JOIN TotalCounts t ON o.CalculationTag = t.CalculationTag
		WHERE o.Position <= t.TotalCount / 2 
	),
	ParsedExpression AS (
		SELECT 
			ope.CalculationTag, 
			f.DateTime,
			ope.ParameterTag,
			ope.Position
		FROM FilteringDuplicates ope
		INNER JOIN (SELECT DISTINCT CalculationTag, DateTime FROM FinalData) f 
			ON ope.CalculationTag = f.CalculationTag
	),
	--Select * from ParsedExpression Order BY CalculationTag, DateTime;
	ExpressionValues AS (
		SELECT 
			pe.CalculationTag,
			pe.DateTime,
			pe.Position,
			CASE
				WHEN fd.Tag = pe.ParameterTag THEN CAST(fd.TagValue AS VARCHAR)
				ELSE pe.ParameterTag
			END AS ParameterTag
		FROM ParsedExpression pe 
		LEFT JOIN FinalData fd ON fd.Tag = pe.ParameterTag AND fd.CalculationTag = pe.CalculationTag AND fd.DateTime = pe.DateTime
	),
	--SELECT CalculationTag, DateTime, ParameterTag, Position
	--FROM ExpressionValues
	--ORDER BY CalculationTag, DateTime, Position;
	FinalExpression AS (
		SELECT 
			CalculationTag, 
			DateTime, 
			STRING_AGG(ParameterTag, '') WITHIN GROUP (ORDER BY Position) AS ComputedExpression
		FROM ExpressionValues
		GROUP BY CalculationTag, DateTime
	)
	SELECT 
		CalculationTag, 
		DateTime, 
		ComputedExpression,
		-- Evaluate the expression dynamically
		CAST(TRY_CONVERT(FLOAT, (ComputedExpression)) AS FLOAT) AS EvaluatedResult
	FROM FinalExpression
	ORDER BY CalculationTag, DateTime;

 
	--SELECT * FROM FinalExpression
	--ORDER BY CalculationTag, DateTime;