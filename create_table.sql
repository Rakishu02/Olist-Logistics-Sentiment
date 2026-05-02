-- ─────────────────────────────────────────────────────────
-- The Entities (The "Who" and "What")
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS olist_customers_dataset (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix INT,
    customer_city VARCHAR(255),
    customer_state VARCHAR(2)
);

CREATE TABLE IF NOT EXISTS olist_sellers_dataset (
    seller_id VARCHAR(50) PRIMARY KEY,
    seller_zip_code_prefix INT,
    seller_city VARCHAR(255),
    seller_state VARCHAR(2)
);

CREATE TABLE IF NOT EXISTS olist_products_dataset (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name VARCHAR(255),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g FLOAT,
    product_length_cm FLOAT,
    product_height_cm FLOAT,
    product_width_cm FLOAT
);

CREATE TABLE IF NOT EXISTS product_category_name_translation (
    product_category_name VARCHAR(255) PRIMARY KEY,
    product_category_name_english VARCHAR(255)
);

-- ─────────────────────────────────────────────────────────
-- The Geography
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS olist_geolocation_dataset (
    geolocation_zip_code_prefix INT,
    geolocation_lat FLOAT,
    geolocation_lng FLOAT,
    geolocation_city VARCHAR(255),
    geolocation_state VARCHAR(2)
);

-- ─────────────────────────────────────────────────────────
-- The Marketing Funnel Extension
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS olist_marketing_qualified_leads_dataset (
    mql_id VARCHAR(50) PRIMARY KEY,
    first_contact_date DATE,
    landing_page_id VARCHAR(255),
    origin VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS olist_closed_deals_dataset (
    mql_id VARCHAR(50) PRIMARY KEY,
    seller_id VARCHAR(50),
    sdr_id VARCHAR(50),
    sr_id VARCHAR(50),
    won_date TIMESTAMP,
    business_segment VARCHAR(255),
    lead_type VARCHAR(255),
    lead_behaviour_profile VARCHAR(255),
    has_company VARCHAR(50),
    has_gtin VARCHAR(50),
    average_stock VARCHAR(50),
    business_type VARCHAR(255),
    declared_product_catalog_size FLOAT,
    declared_monthly_revenue DECIMAL(10,2),
    FOREIGN KEY (mql_id) REFERENCES olist_marketing_qualified_leads_dataset(mql_id)
    -- NOTE: seller_id intentionally has NO foreign key constraint.
    -- The marketing funnel contains closed deals for sellers who were signed up
    -- but never became active on the marketplace (not present in olist_sellers_dataset).
    -- The relationship is maintained via idx_deals_seller_id index for JOIN performance.
);

-- ─────────────────────────────────────────────────────────
-- The Central Hub (Orders)
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS olist_orders_dataset (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50),
    order_status VARCHAR(50),
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES olist_customers_dataset(customer_id)
);

-- ─────────────────────────────────────────────────────────
-- The Order Details
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS olist_order_items_dataset (
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date TIMESTAMP,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id),
    FOREIGN KEY (product_id) REFERENCES olist_products_dataset(product_id),
    FOREIGN KEY (seller_id) REFERENCES olist_sellers_dataset(seller_id)
);

CREATE TABLE IF NOT EXISTS olist_order_payments_dataset (
    order_id VARCHAR(50),
    payment_sequential INT,
    payment_type VARCHAR(50),
    payment_installments INT,
    payment_value DECIMAL(10,2),
    PRIMARY KEY (order_id, payment_sequential),
    FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id)
);

CREATE TABLE IF NOT EXISTS olist_order_reviews_dataset (
    review_id VARCHAR(50),
    order_id VARCHAR(50),
    review_score INT,
    review_comment_title VARCHAR(255),
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id)
);

-- ─────────────────────────────────────────────────────────
-- PERFORMANCE OPTIMIZATIONS (INDEXES)
-- ─────────────────────────────────────────────────────────

-- 1. Foreign Key Indexes (Speeds up JOINs drastically)
-- NOTE: Indexes on PK leading columns (order_id in items/payments, mql_id in deals)
-- are omitted because PostgreSQL already indexes Primary Keys automatically.
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON olist_orders_dataset(customer_id);
CREATE INDEX IF NOT EXISTS idx_items_product_id ON olist_order_items_dataset(product_id);
CREATE INDEX IF NOT EXISTS idx_items_seller_id ON olist_order_items_dataset(seller_id);
CREATE INDEX IF NOT EXISTS idx_reviews_order_id ON olist_order_reviews_dataset(order_id);
CREATE INDEX IF NOT EXISTS idx_deals_seller_id ON olist_closed_deals_dataset(seller_id);

-- 2. "Soft" Foreign Key / Common Join Indexes (For the Geography Table)
-- Since zip_code_prefix isn't a strict FK (it connects Customers/Sellers to Geolocation), 
-- these indexes will optimize the geographic distance calculations and mapping joins.
CREATE INDEX IF NOT EXISTS idx_geo_zip_code ON olist_geolocation_dataset(geolocation_zip_code_prefix);
CREATE INDEX IF NOT EXISTS idx_customer_zip_code ON olist_customers_dataset(customer_zip_code_prefix);
CREATE INDEX IF NOT EXISTS idx_seller_zip_code ON olist_sellers_dataset(seller_zip_code_prefix);

-- 3. Frequently Filtered/Aggregated Columns (Speeds up WHERE and GROUP BY clauses)
CREATE INDEX IF NOT EXISTS idx_orders_status ON olist_orders_dataset(order_status);
CREATE INDEX IF NOT EXISTS idx_orders_purchase_time ON olist_orders_dataset(order_purchase_timestamp);

-- ─────────────────────────────────────────────────────────
-- DATA IMPORT (\copy statements for psql)
-- ─────────────────────────────────────────────────────────
-- Run these commands in psql from the project root directory.
-- The order is important to respect Foreign Key constraints!
-- TRUNCATE ensures the script is safely re-runnable without duplicate key errors.

TRUNCATE TABLE olist_order_reviews_dataset,
               olist_order_payments_dataset,
               olist_order_items_dataset,
               olist_orders_dataset,
               olist_closed_deals_dataset,
               olist_marketing_qualified_leads_dataset,
               olist_geolocation_dataset,
               product_category_name_translation,
               olist_products_dataset,
               olist_sellers_dataset,
               olist_customers_dataset
               CASCADE;

\copy olist_customers_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_sellers_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_products_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy product_category_name_translation FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_geolocation_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_marketing_qualified_leads_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_marketing_qualified_leads_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_closed_deals_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_closed_deals_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_orders_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_order_items_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_order_payments_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy olist_order_reviews_dataset FROM 'C:/Users/fachr/Documents/Kerja/Project Portofolio/Big Project/Dataset/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
