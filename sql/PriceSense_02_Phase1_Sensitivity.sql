-- phase 1: figuring out where demand actually breaks down by price
-- the goal here is to find the exact price points where people stop buying
-- and then check if that behaviour is the same across different customer types
--
-- starting broad (overall distribution) then zooming into personas


-- first thing i want to see: where do orders actually sit across price ranges?
-- this tells me where the bulk of demand is concentrated
-- and where it falls off

SELECT
    price_bucket,
    COUNT(*)                                           AS order_count,
    SUM(quantity)                                      AS units_sold,
    ROUND(SUM(line_revenue), 2)                        AS total_revenue,
    ROUND(AVG(price), 2)                               AS avg_price,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders
FROM (
    SELECT
        line_revenue,
        quantity,
        price,
        CASE
            WHEN price <  10 THEN '01. Under $10'
            WHEN price <  20 THEN '02. $10–$19'
            WHEN price <  30 THEN '03. $20–$29'
            WHEN price <  40 THEN '04. $30–$39'
            WHEN price <  50 THEN '05. $40–$49'
            WHEN price <  75 THEN '06. $50–$74'
            WHEN price < 100 THEN '07. $75–$99'
            WHEN price < 150 THEN '08. $100–$149'
            WHEN price < 200 THEN '09. $150–$199'
            ELSE                   '10. $200+'
        END AS price_bucket
    FROM master_view
) bucketed
GROUP BY price_bucket
ORDER BY price_bucket;


-- now i want to see WHERE demand actually drops between buckets
-- using LAG() to compare each bucket to the one before it
-- anything that drops more than 20% i'm flagging as a real threshold
-- those are the prices people are psychologically resisting

WITH bucket_counts AS (
    SELECT
        CASE
            WHEN price <  10 THEN '01. Under $10'
            WHEN price <  20 THEN '02. $10–$19'
            WHEN price <  30 THEN '03. $20–$29'
            WHEN price <  40 THEN '04. $30–$39'
            WHEN price <  50 THEN '05. $40–$49'
            WHEN price <  75 THEN '06. $50–$74'
            WHEN price < 100 THEN '07. $75–$99'
            WHEN price < 150 THEN '08. $100–$149'
            WHEN price < 200 THEN '09. $150–$199'
            ELSE                   '10. $200+'
        END AS price_bucket,
        COUNT(*) AS order_count
    FROM master_view
    GROUP BY price_bucket
),
with_lag AS (
    SELECT
        price_bucket,
        order_count,
        LAG(order_count) OVER (ORDER BY price_bucket) AS prev_bucket_count
    FROM bucket_counts
)
SELECT
    price_bucket,
    order_count,
    prev_bucket_count,
    ROUND(
        100.0 * (order_count - prev_bucket_count) / prev_bucket_count
    , 2) AS pct_change,
    CASE
        WHEN (100.0 * (order_count - prev_bucket_count) / prev_bucket_count) < -20
        THEN 'threshold here'
        ELSE ''
    END AS flag
FROM with_lag
WHERE prev_bucket_count IS NOT NULL
ORDER BY price_bucket;


-- same bucketing but broken out by persona
-- want to see if 'budget' users really do cluster at lower prices
-- or if the persona labels are basically meaningless for pricing
-- (spoiler from my earlier checks: they might be)

SELECT
    persona,
    price_bucket,
    COUNT(*)                                AS order_count,
    ROUND(AVG(price), 2)                    AS avg_price_paid,
    ROUND(SUM(line_revenue), 2)             AS total_revenue,
    ROUND(100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (PARTITION BY persona), 2
    )                                       AS pct_within_persona
FROM (
    SELECT
        persona,
        price,
        line_revenue,
        CASE
            WHEN price <  10 THEN '01. Under $10'
            WHEN price <  20 THEN '02. $10–$19'
            WHEN price <  30 THEN '03. $20–$29'
            WHEN price <  40 THEN '04. $30–$39'
            WHEN price <  50 THEN '05. $40–$49'
            WHEN price <  75 THEN '06. $50–$74'
            WHEN price < 100 THEN '07. $75–$99'
            WHEN price < 150 THEN '08. $100–$149'
            WHEN price < 200 THEN '09. $150–$199'
            ELSE                   '10. $200+'
        END AS price_bucket
    FROM master_view
    WHERE persona IS NOT NULL
) bucketed
GROUP BY persona, price_bucket
ORDER BY persona, price_bucket;


-- high level summary per persona — avg price, max they've paid, total revenue
-- the variance % at the end is useful: higher variance = more price sensitive
-- a budget user with high variance is unpredictable, which is actually a problem

SELECT
    persona,
    COUNT(*)                   AS total_orders,
    ROUND(MIN(price), 2)       AS min_price,
    ROUND(AVG(price), 2)       AS avg_price,
    ROUND(MAX(price), 2)       AS max_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(
        100.0 * (
            (SUM(price * price) / COUNT(*)) - (AVG(price) * AVG(price))
        ) / (AVG(price) * AVG(price))
    , 2)                       AS price_variance_pct
FROM master_view
WHERE persona IS NOT NULL
GROUP BY persona
ORDER BY avg_price DESC;


-- simple split: how many orders per persona are sub-$20 vs $20+?
-- this is the clearest way to show price sensitivity without overthinking it

SELECT
    persona,
    SUM(CASE WHEN price <  20 THEN 1 ELSE 0 END) AS orders_under_20,
    SUM(CASE WHEN price >= 20 THEN 1 ELSE 0 END) AS orders_20_plus,
    COUNT(*)                                      AS total_orders,
    ROUND(100.0 *
        SUM(CASE WHEN price >= 20 THEN 1 ELSE 0 END) / COUNT(*), 2
    )                                             AS pct_at_20_or_above
FROM master_view
WHERE persona IS NOT NULL
GROUP BY persona
ORDER BY pct_at_20_or_above DESC;


-- checking if channel affects how much people pay
-- like do gym kiosk buyers actually spend more than app buyers?
-- could be useful for channel pricing strategy

SELECT
    persona,
    channel,
    COUNT(*)                    AS order_count,
    ROUND(AVG(price), 2)        AS avg_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue
FROM master_view
WHERE persona IS NOT NULL
  AND channel IS NOT NULL
GROUP BY persona, channel
ORDER BY persona, avg_price DESC;


-- income bracket vs price — this is the cross i actually care about
-- my hunch is income predicts price better than persona label does

SELECT
    income_bracket,
    CASE
        WHEN price <  20 THEN 'budget range (under $20)'
        WHEN price <  50 THEN 'mid range ($20–$49)'
        ELSE                   'premium range ($50+)'
    END                        AS price_tier,
    COUNT(*)                   AS order_count,
    ROUND(AVG(price), 2)       AS avg_price,
    ROUND(SUM(line_revenue), 2) AS total_revenue
FROM master_view
WHERE income_bracket IS NOT NULL
GROUP BY income_bracket, price_tier
ORDER BY income_bracket, price_tier;
