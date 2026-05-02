CREATE OR REPLACE VIEW vw_seller_order_performance AS

-- Step 1: Pre-aggregate the items so there is only ONE row per seller per order
WITH Aggregated_Items AS (
    SELECT 
        order_id,
        seller_id,
        COUNT(order_item_id) AS total_items_sold,
        SUM(price) AS total_order_revenue,
        SUM(freight_value) AS total_freight_cost
    FROM olist_order_items_dataset
    GROUP BY order_id, seller_id
),

-- Step 2: Pre-aggregate reviews (in rare cases an order has multiple reviews, take the most recent or lowest score)
Deduplicated_Reviews AS (
    SELECT 
        order_id,
        MIN(review_score) AS final_review_score, -- Assuming the worst score is the most actionable
        MAX(review_comment_message) AS review_message -- Simplification for text extraction
    FROM olist_order_reviews_dataset
    GROUP BY order_id
)

-- Step 3: The Grand Join (Now perfectly 1:1 at the Seller-Order grain)
SELECT
    mql.mql_id,
    mql.origin AS marketing_channel,
    cd.seller_id,
    cd.business_segment,
    
    agg.total_items_sold,
    agg.total_order_revenue,
    
    o.order_id,
    -- Better precision for Postgres date math:
    DATE_PART('day', o.order_delivered_customer_date::timestamp - o.order_estimated_delivery_date::timestamp) AS logistical_delay_days,
    
    rev.final_review_score,
    rev.review_message

FROM olist_marketing_qualified_leads_dataset AS mql
INNER JOIN olist_closed_deals_dataset AS cd 
    ON mql.mql_id = cd.mql_id
LEFT JOIN Aggregated_Items AS agg 
    ON cd.seller_id = agg.seller_id
LEFT JOIN olist_orders_dataset AS o 
    ON agg.order_id = o.order_id
LEFT JOIN Deduplicated_Reviews AS rev 
    ON o.order_id = rev.order_id;


-- Aggregation at the Order Grain to ensure no fan-out or duplication
WITH Order_Freight_Costs AS (
    SELECT 
        order_id,
        seller_id,
        COUNT(order_item_id) AS total_items_sold,
        SUM(freight_value) AS total_freight_cost,
        SUM(price) AS total_order_revenue
    FROM olist_order_items_dataset
    GROUP BY order_id, seller_id
),

-- Aggregate product details (taking the dominant category if multiple products exist in an order)
Order_Product_Context AS (
    SELECT
        oi.order_id,
        MIN(pt.product_category_name_english) AS primary_product_category -- Min forces one category
    FROM olist_order_items_dataset AS oi
    JOIN olist_products_dataset AS p ON oi.product_id = p.product_id
    JOIN product_category_name_translation AS pt ON p.product_category_name = pt.product_category_name
    GROUP BY oi.order_id
),

-- Aggregate customer location (One customer per order)
Order_Customer_Location AS (
    SELECT
        o.order_id,
        c.customer_state
    FROM olist_orders_dataset AS o
    JOIN olist_customers_dataset AS c ON o.customer_id = c.customer_id
)

-- The Final "Operations Master" Join
SELECT
    o.order_id,
    o.order_purchase_timestamp,
    cust.customer_state,
    prod.primary_product_category,
    fgt.total_items_sold,
    fgt.total_order_revenue,
    fgt.total_freight_cost
FROM olist_orders_dataset AS o
JOIN Order_Freight_Costs AS fgt ON o.order_id = fgt.order_id
JOIN Order_Product_Context AS prod ON o.order_id = prod.order_id
JOIN Order_Customer_Location AS cust ON o.order_id = cust.order_id
WHERE o.order_status = 'delivered'; -- Only analyze completed logistical cycles