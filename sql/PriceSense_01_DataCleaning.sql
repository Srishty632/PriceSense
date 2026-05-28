-- okay so before i touch anything, let me actually look at what's broken in this data.
-- ran some quick checks and here's what i found:
--
--   transactions  → 1,067 rows have negative prices (refunds? bad entries? no idea)
--                   also one transaction at $18,641 which is clearly not a protein bar
--                   P99 sits at $223 so i'm using $225 as the cutoff — feels reasonable
--
--   consumer_insights → 276 users have no persona label at all
--                       can't do segment analysis on blank rows so i'm dropping them
--
--   product_metadata  → someone typed "Proten Shake" (missing 'i')
--                       also "Protein bar " with a trailing space that breaks grouping
--                       4 rows with no category — just labelling those "Unknown"
--
--   geography         → 4,691 rows say city_tier = 'Unknown'
--                       keeping them for state-level stuff but excluding from tier comparisons
--
--   competitor_pricing → 58 null prices, nothing to do there except skip them
--
-- i'm doing all the cleaning as VIEWs so the raw tables stay untouched.
-- if something breaks downstream i can always come back and fix the logic here.


-- transactions: stripping out the garbage
-- negative prices = returns or errors, both useless for pricing analysis
-- $225 ceiling because one outlier at $18k would destroy every average

DROP VIEW IF EXISTS clean_transactions;
CREATE VIEW clean_transactions AS
SELECT
    order_id,
    user_id,
    product_id,
    price,
    quantity,
    timestamp,
    channel,
    ROUND(price * quantity, 2) AS line_revenue   -- just useful to have this precomputed
FROM transactions
WHERE price    > 0
  AND price   <= 225
  AND quantity > 0;


-- consumer_insights: drop the 276 rows where persona is blank
-- tried to see if i could infer persona from other columns but there's no clean pattern
-- safer to just exclude than guess wrong

DROP VIEW IF EXISTS clean_consumer_insights;
CREATE VIEW clean_consumer_insights AS
SELECT
    user_id,
    TRIM(persona)          AS persona,
    TRIM(trend_affinity)   AS trend_affinity,
    age_group,
    gender_identity,
    income_bracket,
    dietary_restriction
FROM consumer_insights
WHERE persona IS NOT NULL
  AND TRIM(persona) != '';


-- product_metadata: fixing the typos before they mess up grouping
-- "Proten Shake" and "Protein Shake" would show as two separate categories otherwise
-- same issue with "Protein bar " (trailing space) vs "Protein Bar"

DROP VIEW IF EXISTS clean_product_metadata;
CREATE VIEW clean_product_metadata AS
SELECT
    product_id,
    CASE
        WHEN category IS NULL OR TRIM(category) = '' THEN 'Unknown'
        WHEN TRIM(category) = 'Proten Shake'         THEN 'Protein Shake'
        WHEN TRIM(category) = 'Protein bar'           THEN 'Protein Bar'
        WHEN TRIM(category) = 'Protein bar '          THEN 'Protein Bar'
        ELSE TRIM(category)
    END AS category,
    claims,
    COALESCE(NULLIF(TRIM(ingredient_tags), ''), 'unlisted') AS ingredient_tags,
    pack_size
FROM product_metadata;


-- geography: keeping 'Unknown' tier rows for state-level queries
-- but this clean version is for anything that needs tier comparisons

DROP VIEW IF EXISTS clean_geography;
CREATE VIEW clean_geography AS
SELECT
    order_id,
    state,
    city_tier,
    occasion
FROM geography_occasion
WHERE city_tier != 'Unknown'
  AND city_tier IS NOT NULL;


-- competitor pricing: just averaging out each competitor product
-- since they have multiple price observations over time (price history basically)
-- null prices are skipped, 58 of them

DROP VIEW IF EXISTS clean_competitor_pricing;
CREATE VIEW clean_competitor_pricing AS
SELECT
    competitor_product_id,
    ROUND(AVG(price), 2) AS avg_price,
    ROUND(MIN(price), 2) AS min_price,
    ROUND(MAX(price), 2) AS max_price,
    COUNT(*)             AS how_many_observations
FROM competitor_pricing
WHERE price IS NOT NULL
GROUP BY competitor_product_id;


-- this is the main view everything else uses
-- joining all four clean tables together
-- using LEFT JOIN for geography because not every transaction has geo data
-- and i don't want to lose transactions just because geography is missing

DROP VIEW IF EXISTS master_view;
CREATE VIEW master_view AS
SELECT
    t.order_id,
    t.user_id,
    t.product_id,
    t.price,
    t.quantity,
    t.line_revenue,
    t.channel,
    t.timestamp,

    c.persona,
    c.trend_affinity,
    c.age_group,
    c.income_bracket,
    c.dietary_restriction,

    p.category,
    p.claims,
    p.ingredient_tags,
    p.pack_size,

    g.state,
    g.city_tier,
    g.occasion

FROM clean_transactions       t
LEFT JOIN clean_consumer_insights  c ON t.user_id    = c.user_id
LEFT JOIN clean_product_metadata   p ON t.product_id = p.product_id
LEFT JOIN geography_occasion       g ON t.order_id   = g.order_id;

-- quick sanity check after running this:
-- SELECT COUNT(*) FROM master_view;
-- should be around 48,000
