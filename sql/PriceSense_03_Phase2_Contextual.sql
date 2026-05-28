-- phase 2: does context actually change what people pay?
-- specifically looking at three things:
--   1. do trend claims (keto, vegan, etc.) justify higher prices?
--   2. does geography (state, city tier) shift price tolerance?
--   3. do certain purchase occasions (gym, fasting, late-night) correlate with paying more?
--
-- this is where the actual pricing recommendations come from


-- claims analysis
-- the claims column is a comma-separated mess so i'm matching with LIKE
-- not perfect but covers all the main ones in the data
-- want to know: does a "keto" claim actually mean people pay more?

SELECT
    claim_tag,
    COUNT(DISTINCT m.order_id)   AS order_count,
    ROUND(AVG(m.price), 2)       AS avg_price,
    ROUND(SUM(m.line_revenue), 2) AS total_revenue,
    ROUND(AVG(m.quantity), 2)    AS avg_units_per_order
FROM master_view m
JOIN (
    SELECT product_id, 'high-protein'  AS claim_tag FROM clean_product_metadata WHERE claims LIKE '%high-protein%'
    UNION ALL
    SELECT product_id, 'plant-based'   FROM clean_product_metadata WHERE claims LIKE '%plant-based%'
    UNION ALL
    SELECT product_id, 'clean-label'   FROM clean_product_metadata WHERE claims LIKE '%clean-label%'
    UNION ALL
    SELECT product_id, 'low-sugar'     FROM clean_product_metadata WHERE claims LIKE '%low-sugar%'
    UNION ALL
    SELECT product_id, 'vegan'         FROM clean_product_metadata WHERE claims LIKE '%vegan%'
    UNION ALL
    SELECT product_id, 'halal'         FROM clean_product_metadata WHERE claims LIKE '%halal%'
    UNION ALL
    SELECT product_id, 'kosher'        FROM clean_product_metadata WHERE claims LIKE '%kosher%'
    UNION ALL
    SELECT product_id, 'keto'          FROM clean_product_metadata WHERE claims LIKE '%keto%'
    UNION ALL
    SELECT product_id, 'nut-free'      FROM clean_product_metadata WHERE claims LIKE '%nut-free%'
    UNION ALL
    SELECT product_id, 'jain-friendly' FROM clean_product_metadata WHERE claims LIKE '%jain-friendly%'
    UNION ALL
    SELECT product_id, 'gluten-free'   FROM clean_product_metadata WHERE claims LIKE '%gluten-free%'
) claim_map ON m.product_id = claim_map.product_id
GROUP BY claim_tag
ORDER BY avg_price DESC;


-- category level — which product types actually sell at a premium?
-- also checking min/max to see how wide the price range is within each category

SELECT
    category,
    COUNT(*)                     AS order_count,
    ROUND(AVG(price), 2)         AS avg_price,
    ROUND(MIN(price), 2)         AS min_price,
    ROUND(MAX(price), 2)         AS max_price,
    ROUND(SUM(line_revenue), 2)  AS total_revenue,
    ROUND(SUM(quantity), 0)      AS total_units
FROM master_view
WHERE category IS NOT NULL
GROUP BY category
ORDER BY avg_price DESC;


-- does pack size affect how much people spend?
-- a 4-pack should have higher order value even if per-unit price is lower

SELECT
    pack_size,
    COUNT(*)                    AS order_count,
    ROUND(AVG(price), 2)        AS avg_price_per_order,
    ROUND(AVG(quantity), 2)     AS avg_units_ordered,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (), 2
    )                           AS pct_of_all_orders
FROM master_view
WHERE pack_size IS NOT NULL
GROUP BY pack_size
ORDER BY avg_price_per_order DESC;


-- state by state — which states are paying more on average?
-- top 20 only, sorted by avg price
-- useful for deciding where to push premium SKUs

SELECT
    state,
    COUNT(*)                    AS order_count,
    ROUND(AVG(price), 2)        AS avg_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(SUM(quantity), 0)     AS total_units
FROM master_view
WHERE state IS NOT NULL
GROUP BY state
ORDER BY avg_price DESC
LIMIT 20;


-- tier 1 vs tier 2 vs tier 3
-- my guess going in was tier 1 (metro) would win but the data surprised me here
-- leaving the result to speak for itself

SELECT
    city_tier,
    COUNT(*)                    AS order_count,
    ROUND(AVG(price), 2)        AS avg_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(SUM(quantity), 0)     AS total_units,
    ROUND(100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (), 2
    )                           AS pct_of_orders
FROM master_view
WHERE city_tier IS NOT NULL
  AND city_tier != 'Unknown'
GROUP BY city_tier
ORDER BY avg_price DESC;


-- occasions — do people spend more when buying for a specific purpose?
-- gym, marathon prep, religious fasting are the "high intent" ones i'm watching

SELECT
    occasion,
    COUNT(*)                    AS order_count,
    ROUND(AVG(price), 2)        AS avg_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(AVG(quantity), 2)     AS avg_units_per_order
FROM master_view
WHERE occasion IS NOT NULL
GROUP BY occasion
ORDER BY avg_price DESC;


-- persona × occasion cross — this is the granular cut i need for recommendations
-- e.g. a premium user buying for gym prep is probably the least price sensitive combo

SELECT
    persona,
    occasion,
    COUNT(*)                    AS order_count,
    ROUND(AVG(price), 2)        AS avg_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue
FROM master_view
WHERE persona  IS NOT NULL
  AND occasion IS NOT NULL
GROUP BY persona, occasion
ORDER BY avg_price DESC
LIMIT 30;


-- revenue per order by city tier × persona
-- this is the metric i care about most for pricing strategy
-- high revenue per order = that combination tolerates premium pricing

SELECT
    city_tier,
    persona,
    COUNT(*)                               AS order_count,
    ROUND(AVG(price), 2)                   AS avg_price,
    ROUND(SUM(line_revenue), 2)            AS total_revenue,
    ROUND(SUM(line_revenue) / COUNT(*), 2) AS revenue_per_order
FROM master_view
WHERE city_tier IS NOT NULL
  AND city_tier != 'Unknown'
  AND persona   IS NOT NULL
GROUP BY city_tier, persona
ORDER BY city_tier, revenue_per_order DESC;


-- benchmarking our prices against competitors
-- using a CROSS JOIN since competitor data isn't category-specific
-- (they're a different product set, so i'm comparing at the aggregate level)
-- flags anything we're clearly under or over pricing

WITH our_prices AS (
    SELECT
        category,
        ROUND(AVG(price), 2) AS our_avg_price,
        COUNT(*)             AS our_order_count
    FROM master_view
    WHERE category IS NOT NULL
    GROUP BY category
),
comp_summary AS (
    SELECT
        ROUND(AVG(avg_price), 2) AS comp_avg,
        ROUND(MIN(min_price), 2) AS comp_min,
        ROUND(MAX(max_price), 2) AS comp_max
    FROM clean_competitor_pricing
)
SELECT
    o.category,
    o.our_avg_price,
    c.comp_avg                             AS competitor_avg,
    c.comp_min                             AS competitor_floor,
    c.comp_max                             AS competitor_ceiling,
    ROUND(o.our_avg_price - c.comp_avg, 2) AS gap_vs_competitor,
    CASE
        WHEN o.our_avg_price < c.comp_min  THEN 'underpriced — room to raise'
        WHEN o.our_avg_price > c.comp_max  THEN 'overpriced — watch churn risk'
        WHEN o.our_avg_price < c.comp_avg  THEN 'slightly below market'
        WHEN o.our_avg_price > c.comp_avg  THEN 'slightly above market'
        ELSE 'at market rate'
    END                                    AS where_we_sit
FROM our_prices  o
CROSS JOIN comp_summary c
ORDER BY gap_vs_competitor DESC;


-- do users who follow certain trends actually pay more?
-- e.g. a gut-health affinity user vs a general user — does it show in their basket?

SELECT
    trend_affinity,
    COUNT(*)                    AS order_count,
    ROUND(AVG(price), 2)        AS avg_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(AVG(quantity), 2)     AS avg_basket_size
FROM master_view
WHERE trend_affinity IS NOT NULL
GROUP BY trend_affinity
ORDER BY avg_price DESC;


-- final output: what price band should we target per persona per city tier?
-- picking the band with the highest revenue per order as "recommended"
-- this is what goes directly into the slide on launch pricing

WITH ranked AS (
    SELECT
        persona,
        city_tier,
        CASE
            WHEN price <  20 THEN 'under $20'
            WHEN price <  50 THEN '$20–$49'
            ELSE                   '$50 and above'
        END                                    AS price_band,
        COUNT(*)                               AS order_count,
        ROUND(SUM(line_revenue), 2)            AS total_revenue,
        ROUND(SUM(line_revenue)/COUNT(*), 2)   AS revenue_per_order,
        ROW_NUMBER() OVER (
            PARTITION BY persona, city_tier
            ORDER BY SUM(line_revenue)/COUNT(*) DESC
        ) AS rn
    FROM master_view
    WHERE persona   IS NOT NULL
      AND city_tier IS NOT NULL
      AND city_tier != 'Unknown'
    GROUP BY persona, city_tier, price_band
)
SELECT
    persona,
    city_tier,
    price_band         AS recommended_launch_range,
    order_count,
    revenue_per_order
FROM ranked
WHERE rn = 1
ORDER BY persona, city_tier;
