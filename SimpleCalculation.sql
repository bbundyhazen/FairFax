--CREATE PROCEDURE ProcessCalculatedTags_CTE
--AS
--BEGIN
WITH StandardCalculations AS (
    SELECT [Tag], [Calculation Type] AS CalculationType, [Calculation Parameters Tag] AS Parameters
    FROM [dbo].[Tags]
    WHERE [Tag Class] = 'Calc'
        AND [Custom Calculation] IS NULL
        AND ([Calculation Type] = '+' OR [Calculation Type] = '-')
),
-- Step 2: Parse Parameters
ParsedParameters AS (
    SELECT sc.Tag AS CalculationTag, TRIM(value) AS Tag
    FROM StandardCalculations sc
    CROSS APPLY STRING_SPLIT(sc.Parameters, ',')
),
-- Step 3: Retrieve Data for Tags
RetrievedData AS (
    SELECT pp.CalculationTag, pp.Tag, d.Value
    FROM ParsedParameters pp
    INNER JOIN [dbo].[Data] d ON pp.Tag = d.Tag
),
-- Step 4: Perform Calculations
SimpleCalculatedResults AS (
    SELECT
        rd.CalculationTag AS Tag,
        sc.CalculationType,
        CASE 
            -- Addition
            WHEN sc.CalculationType = '+' AND CHARINDEX('NOTNULLS', rd.CalculationTag) > 0 THEN 
                SUM(CASE WHEN rd.Value IS NOT NULL THEN rd.Value ELSE 0 END)
            WHEN sc.CalculationType = '+' AND CHARINDEX('NULLS', rd.CalculationTag) > 0 THEN 
                CASE WHEN COUNT(CASE WHEN rd.Value IS NULL THEN 1 END) > 0 THEN NULL
                        ELSE SUM(rd.Value) 
                END

            -- Subtraction
            WHEN sc.CalculationType = '-' AND CHARINDEX('NOTNULLS', rd.CalculationTag) > 0 THEN 
                SUM(CASE WHEN rd.Value IS NOT NULL THEN rd.Value ELSE 0 END) 
                - (SELECT SUM(CASE WHEN rd2.Value IS NOT NULL THEN rd2.Value ELSE 0 END) 
                    FROM [dbo].[Data] rd2 
                    WHERE rd2.Tag NOT IN (SELECT Tag FROM ParsedParameters WHERE CalculationTag = rd.CalculationTag))
            WHEN sc.CalculationType = '-' AND CHARINDEX('NULLS', rd.CalculationTag) > 0 THEN 
                CASE WHEN COUNT(CASE WHEN rd.Value IS NULL THEN 1 END) > 0 THEN NULL
                        ELSE SUM(rd.Value) - 
                            (SELECT SUM(rd2.Value) 
                             FROM [dbo].[Data] rd2 
                             WHERE rd2.Tag NOT IN (SELECT Tag FROM ParsedParameters WHERE CalculationTag = rd.CalculationTag)) 
                END
        END AS CalculatedValue
    FROM RetrievedData rd
		INNER JOIN StandardCalculations sc ON rd.CalculationTag = sc.Tag
    GROUP BY rd.CalculationTag, sc.CalculationType
)
SELECT * 
FROM SimpleCalculatedResults;



			---- Multiplication
			--WHEN sc.CalculationType = '*' THEN 
			--	CASE 
			--		WHEN CHARINDEX('MULTIPLY.NULLS', rd.CalculationTag) > 0 THEN 
			--			CASE WHEN COUNT(CASE WHEN rd.Value IS NULL THEN 1 END) > 0 THEN NULL
			--					ELSE EXP(SUM(LOG(NULLIF(rd.Value, 0)))) END
			--		WHEN CHARINDEX('MULTIPLY.ZEROES', rd.CalculationTag) > 0 THEN 
			--			CASE WHEN COUNT(CASE WHEN rd.Value = 0 THEN 1 END) > 0 THEN 0
			--					ELSE EXP(SUM(LOG(NULLIF(rd.Value, 0)))) END
			--		WHEN CHARINDEX('MULTIPLY.NONZEROES', rd.CalculationTag) > 0 THEN 
			--			CASE WHEN COUNT(CASE WHEN rd.Value IS NULL THEN 1 END) > 0 THEN 1
			--					ELSE EXP(SUM(LOG(NULLIF(rd.Value, 0)))) END
			--	END

			---- Division
			--WHEN sc.CalculationType = '/' THEN 
			--	CASE 
			--		WHEN CHARINDEX('DIVIDE.NULLS', rd.CalculationTag) > 0 THEN 
			--			CASE WHEN COUNT(CASE WHEN rd.Value IS NULL THEN 1 END) > 0 THEN NULL
			--					ELSE EXP(SUM(LOG(NULLIF(rd.Value, 0)))) END
			--		WHEN CHARINDEX('DIVIDE.UNDEFINED.NULLS', rd.CalculationTag) > 0 THEN 
			--			CASE WHEN COUNT(CASE WHEN rd.Value IS NULL THEN 1 END) > 0 OR COUNT(CASE WHEN rd.Value = 0 THEN 1 END) > 0 THEN NULL
			--					ELSE EXP(SUM(LOG(NULLIF(rd.Value, 0)))) END
			--		WHEN CHARINDEX('DIVIDE.NOTNULLS', rd.CalculationTag) > 0 THEN 
			--			CASE WHEN COUNT(CASE WHEN rd.Value IS NULL THEN 1 END) > 0 THEN 1
			--					WHEN COUNT(CASE WHEN rd.Value = 0 THEN 1 END) > 0 THEN NULL
			--					ELSE EXP(SUM(LOG(NULLIF(rd.Value, 0)))) END
			--		WHEN CHARINDEX('DIVIDE.CHAINED.ZEROES', rd.CalculationTag) > 0 THEN 
			--			CASE WHEN COUNT(CASE WHEN rd.Value = 0 THEN 1 END) > 0 THEN 0
			--					ELSE EXP(SUM(LOG(NULLIF(rd.Value, 0)))) END
			--	END


