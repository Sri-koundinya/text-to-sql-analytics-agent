-- Deterministic seed data for the retail analytics demo.
--
-- Runs after init.sql (schema + analytics_reader role). Every random() call below
-- is driven by setseed(), and every INSERT has an explicit ORDER BY, so the same
-- Postgres major version always produces byte-identical tables. Evaluation results
-- (roadmap item 2) depend on this: do not use random() without the seed, and do not
-- remove the ORDER BY clauses or the parallelism setting.
--
-- Shape of the data:
--   customers     2,000  signups 2023-01-01 .. 2025-06-30, weighted toward large metros
--   products         48  8 categories, fixed catalogue
--   orders       ~24,800 2023-01-01 .. 2025-12-31, ~86% completed / 9% cancelled / 5% refunded,
--                        growth over time plus a Q4 (festive season) bump
--   order_items  ~41,000 1-4 lines per order, popularity skew, occasional 10% discount

-- Parallel workers would make row order (and therefore random() assignment) nondeterministic.
SET max_parallel_workers_per_gather = 0;
DO $$ BEGIN PERFORM setseed(0.42); END $$;

-- ---------------------------------------------------------------------------
-- Products: fixed catalogue (no randomness). Earlier rows are more popular.
-- ---------------------------------------------------------------------------
INSERT INTO products (product_name, category, unit_price) VALUES
  ('Wireless Headphones', 'Electronics', 79.99),
  ('Running Shoes', 'Sports', 89.50),
  ('Water Bottle', 'Sports', 18.00),
  ('Coffee Maker', 'Home', 65.00),
  ('Mechanical Keyboard', 'Electronics', 119.00),
  ('Desk Lamp', 'Home', 42.75),
  ('Yoga Mat', 'Sports', 29.99),
  ('Face Moisturizer', 'Beauty', 24.50),
  ('Basmati Rice 5kg', 'Grocery', 14.25),
  ('Bluetooth Speaker', 'Electronics', 54.99),
  ('Cotton T-Shirt', 'Apparel', 15.99),
  ('Paperback Novel', 'Books', 12.99),
  ('Smartwatch', 'Electronics', 199.00),
  ('Green Tea 100 bags', 'Grocery', 9.75),
  ('Denim Jeans', 'Apparel', 49.00),
  ('Non-stick Frying Pan', 'Home', 34.50),
  ('Building Blocks Set', 'Toys', 39.99),
  ('Sunscreen SPF 50', 'Beauty', 16.75),
  ('USB-C Charger', 'Electronics', 25.00),
  ('Cricket Bat', 'Sports', 74.00),
  ('Hoodie', 'Apparel', 44.50),
  ('Cookbook', 'Books', 27.50),
  ('Olive Oil 1L', 'Grocery', 13.40),
  ('Bedsheet Set', 'Home', 38.00),
  ('Board Game', 'Toys', 32.00),
  ('Shampoo', 'Beauty', 11.20),
  ('Laptop Stand', 'Electronics', 36.99),
  ('Dumbbell Pair 5kg', 'Sports', 45.00),
  ('Rain Jacket', 'Apparel', 69.00),
  ('Business Strategy Book', 'Books', 22.00),
  ('Almonds 1kg', 'Grocery', 18.60),
  ('Throw Pillow', 'Home', 19.99),
  ('Remote Control Car', 'Toys', 48.50),
  ('Lipstick', 'Beauty', 14.00),
  ('Tablet 10 inch', 'Electronics', 289.00),
  ('Badminton Racket', 'Sports', 33.25),
  ('Formal Shirt', 'Apparel', 37.50),
  ('Children''s Picture Book', 'Books', 9.99),
  ('Dark Chocolate Pack', 'Grocery', 7.80),
  ('Air Purifier', 'Home', 149.00),
  ('Puzzle 1000 pieces', 'Toys', 21.00),
  ('Perfume', 'Beauty', 58.00),
  ('Noise Cancelling Earbuds', 'Electronics', 129.00),
  ('Cycling Helmet', 'Sports', 52.00),
  ('Winter Scarf', 'Apparel', 22.40),
  ('Science Fiction Box Set', 'Books', 46.00),
  ('Filter Coffee Powder', 'Grocery', 8.90),
  ('Stand Mixer', 'Home', 219.00);

-- ---------------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------------
INSERT INTO customers (full_name, city, state, signup_date)
WITH draws AS MATERIALIZED (
  SELECT g, random() AS r_first, random() AS r_last, random() AS r_city, random() AS r_date
  FROM generate_series(1, 2000) AS g
  ORDER BY g
),
first_names AS (
  SELECT ARRAY['Aarav','Diya','Kabir','Meera','Rohan','Ananya','Vihaan','Isha','Arjun','Saanvi',
               'Aditya','Kavya','Reyansh','Priya','Krishna','Nisha','Siddharth','Pooja','Rahul','Sneha',
               'Vikram','Lakshmi','Aryan','Neha','Karthik','Divya','Nikhil','Riya','Manish','Tanvi'] AS a
),
last_names AS (
  SELECT ARRAY['Sharma','Patel','Singh','Iyer','Gupta','Reddy','Nair','Mehta','Kumar','Das',
               'Joshi','Rao','Menon','Chopra','Bose','Pillai','Verma','Shah','Kulkarni','Banerjee'] AS a
),
-- Repeated entries weight the draw toward larger metros.
cities AS (
  SELECT ARRAY['Bengaluru','Bengaluru','Bengaluru','Mumbai','Mumbai','Mumbai','Delhi','Delhi','Delhi',
               'Chennai','Chennai','Hyderabad','Hyderabad','Pune','Pune','Kolkata','Kolkata',
               'Ahmedabad','Jaipur','Kochi','Lucknow','Chandigarh','Mysuru','Coimbatore'] AS city,
         ARRAY['Karnataka','Karnataka','Karnataka','Maharashtra','Maharashtra','Maharashtra','Delhi','Delhi','Delhi',
               'Tamil Nadu','Tamil Nadu','Telangana','Telangana','Maharashtra','Maharashtra','West Bengal','West Bengal',
               'Gujarat','Rajasthan','Kerala','Uttar Pradesh','Chandigarh','Karnataka','Tamil Nadu'] AS state
)
SELECT
  f.a[1 + floor(d.r_first * array_length(f.a, 1))::int] || ' ' ||
  l.a[1 + floor(d.r_last * array_length(l.a, 1))::int],
  c.city[1 + floor(d.r_city * array_length(c.city, 1))::int],
  c.state[1 + floor(d.r_city * array_length(c.state, 1))::int],
  DATE '2023-01-01' + floor(d.r_date * (DATE '2025-06-30' - DATE '2023-01-01' + 1))::int
FROM draws d CROSS JOIN first_names f CROSS JOIN last_names l CROSS JOIN cities c
ORDER BY d.g;

-- ---------------------------------------------------------------------------
-- Orders
-- Candidate dates are drawn uniformly over 2023-2025; Q4 candidates get a second
-- chance to be kept (festive bump). Each order's date is never before its
-- customer's signup date, which also produces organic growth over time.
-- ---------------------------------------------------------------------------
INSERT INTO orders (customer_id, order_date, status)
WITH draws AS MATERIALIZED (
  SELECT g, random() AS r_cust, random() AS r_date, random() AS r_keep, random() AS r_status
  FROM generate_series(1, 28000) AS g
  ORDER BY g
),
shaped AS (
  SELECT
    d.g,
    -- r^1.6 skews toward lower customer ids: a loyal core of repeat buyers plus a long tail.
    1 + floor(power(d.r_cust, 1.6) * 2000)::int AS customer_id,
    DATE '2023-01-01' + floor(d.r_date * (DATE '2025-12-31' - DATE '2023-01-01' + 1))::int AS candidate_date,
    d.r_keep,
    d.r_status
  FROM draws d
)
SELECT
  s.customer_id,
  GREATEST(s.candidate_date, c.signup_date) AS order_date,
  CASE WHEN s.r_status < 0.86 THEN 'completed'
       WHEN s.r_status < 0.95 THEN 'cancelled'
       ELSE 'refunded' END
FROM shaped s
JOIN customers c ON c.customer_id = s.customer_id
-- Keep ~85% of non-Q4 candidates and all Q4 candidates.
WHERE EXTRACT(MONTH FROM s.candidate_date) >= 10 OR s.r_keep < 0.85
ORDER BY GREATEST(s.candidate_date, c.signup_date), s.g;

-- ---------------------------------------------------------------------------
-- Order items
-- ---------------------------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
WITH line_counts AS MATERIALIZED (
  SELECT order_id, 1 + floor(random() * random() * 4.2)::int AS n_lines
  FROM orders
  ORDER BY order_id
),
lines AS MATERIALIZED (
  SELECT lc.order_id, i AS line_no, random() AS r_product, random() AS r_qty, random() AS r_discount
  FROM line_counts lc
  CROSS JOIN LATERAL generate_series(1, LEAST(lc.n_lines, 4)) AS i
  ORDER BY lc.order_id, i
),
product_count AS (
  SELECT count(*)::int AS n FROM products
)
SELECT
  l.order_id,
  p.product_id,
  CASE WHEN l.r_qty < 0.70 THEN 1
       WHEN l.r_qty < 0.90 THEN 2
       WHEN l.r_qty < 0.97 THEN 3
       ELSE 5 END AS quantity,
  CASE WHEN l.r_discount < 0.12 THEN round(p.unit_price * 0.90, 2)
       ELSE p.unit_price END AS unit_price
FROM lines l
CROSS JOIN product_count pc
JOIN products p ON p.product_id = 1 + floor(power(l.r_product, 1.4) * pc.n)::int
ORDER BY l.order_id, l.line_no;

ANALYZE customers;
ANALYZE products;
ANALYZE orders;
ANALYZE order_items;

RESET max_parallel_workers_per_gather;
