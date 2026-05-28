-- these are the 5 findings that go into the deck
-- each query here directly answers one slide's worth of content
-- i've added the "so what" in the comments so i don't forget when building slides


-- finding 1: the $20 wall
-- 37% of all orders sit in the $10–$19 range
-- crossing into $20+ causes a 65% drop in order count
-- $19.99 is the clearest psychological ceiling in this dataset
-- implication: if you're launching at $22, you're fighting this cliff head on

SELECT
    price_bucket,
    order_count,
    pct_of_orders,
    CASE
        WHEN pct_change < -20 THEN 'demand drops here'
        ELSE ''
    END AS note
FROM (
    WITH counts AS (
        SELECT
            CASE
                WHEN price <  10 THEN '01. under $10'
                WHEN price <  20 THEN '02. $10–$19'
                WHEN price <  30 THEN '03. $20–$29'
                WHEN price <  40 THEN '04. $30–$39'
                WHEN price <  50 THEN '05. $40–$49'
                WHEN price <  75 THEN '06. $50–$74'
                WHEN price < 100 THEN '07. $75–$99'
                WHEN price < 150 THEN '08. $100–$149'
                WHEN price < 200 THEN '09. $150–$199'
                ELSE                  '10. $200+'
            END AS price_bucket,
            COUNT(*) AS order_count,
            ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders
        FROM master_view
        GROUP BY price_bucket
    )
    SELECT
        price_bucket,
        order_count,
        pct_of_orders,
        ROUND(100.0 * (order_count - LAG(order_count)
            OVER (ORDER BY price_bucket)) /
            LAG(order_count) OVER (ORDER BY price_bucket), 2
        ) AS pct_change
    FROM counts
)
ORDER BY price_bucket;


-- finding 2: persona labels don't predict price behaviour
-- all four personas (budget, casual, fitness, premium) average around $30
-- the "budget" persona isn't actually paying less
-- income bracket is a stronger signal — see below
-- implication: don't build pricing tiers around persona names,
--              build them around income bracket instead

SELECT
    persona,
    income_bracket,
    COUNT(*) AS orders,
    ROUND(AVG(price), 2) AS avg_price
FROM master_view
WHERE persona IS NOT NULL
  AND income_bracket IS NOT NULL
GROUP BY persona, income_bracket
ORDER BY persona, avg_price DESC;


-- finding 3: which claims actually earn a premium?
-- keto (+$7.71 above avg) and low-sugar (+$6.99) are the real winners
-- plant-based is $8.69 BELOW market average — it's oversaturated as a claim
-- high-protein is barely above average (+$1.50) despite being the core product type
-- implication: lead with keto/low-sugar in your product claims,
--              don't lean on "high-protein" alone as a differentiator

SELECT
    claim_tag,
    ROUND(AVG(m.price), 2)                      AS avg_price,
    ROUND(AVG(m.price) - overall.avg_all, 2)    AS vs_overall_avg,
    CASE
        WHEN AVG(m.price) > overall.avg_all * 1.15 THEN 'worth the premium claim'
        WHEN AVG(m.price) < overall.avg_all * 0.90 THEN 'not pulling its weight'
        ELSE 'about average'
    END AS verdict
FROM master_view m
JOIN (
    SELECT product_id, 'high-protein' AS claim_tag FROM clean_product_metadata WHERE claims LIKE '%high-protein%'
    UNION ALL SELECT product_id, 'plant-based'  FROM clean_product_metadata WHERE claims LIKE '%plant-based%'
    UNION ALL SELECT product_id, 'clean-label'  FROM clean_product_metadata WHERE claims LIKE '%clean-label%'
    UNION ALL SELECT product_id, 'low-sugar'    FROM clean_product_metadata WHERE claims LIKE '%low-sugar%'
    UNION ALL SELECT product_id, 'vegan'        FROM clean_product_metadata WHERE claims LIKE '%vegan%'
    UNION ALL SELECT product_id, 'keto'         FROM clean_product_metadata WHERE claims LIKE '%keto%'
) c ON m.product_id = c.product_id
CROSS JOIN (SELECT ROUND(AVG(price), 2) AS avg_all FROM master_view) overall
GROUP BY claim_tag
ORDER BY avg_price DESC;


-- finding 4: tier 2 cities outperform tier 1 on revenue per order
-- tier 1 (metros) have more orders but lower revenue per order
-- tier 2 is actually more efficient to sell into
-- implication: don't dump the entire marketing budget into metros
--              tier 2 is underserved and paying just as much

SELECT
    city_tier,
    COUNT(*)                               AS orders,
    ROUND(AVG(price), 2)                   AS avg_price,
    ROUND(SUM(line_revenue), 2)            AS total_revenue,
    ROUND(SUM(line_revenue) / COUNT(*), 2) AS revenue_per_order
FROM master_view
WHERE city_tier NOT IN ('Unknown')
  AND city_tier IS NOT NULL
GROUP BY city_tier
ORDER BY revenue_per_order DESC;


-- finding 5: gym and religious-fasting buyers are least price sensitive
-- these are "high intent" moments — people buying with a specific purpose in mind
-- they're not browsing, they've already decided they need the product
-- festive and daily-snack occasions sit at the bottom (more casual, more price aware)
-- implication: price gym-channel and fasting-occasion SKUs 8–10% higher

SELECT
    occasion,
    COUNT(*)                               AS orders,
    ROUND(AVG(price), 2)                   AS avg_price,
    ROUND(AVG(price) - baseline.avg_all, 2) AS vs_overall_avg
FROM master_view
CROSS JOIN (SELECT ROUND(AVG(price), 2) AS avg_all FROM master_view) baseline
WHERE occasion IS NOT NULL
GROUP BY occasion
ORDER BY avg_price DESC;
