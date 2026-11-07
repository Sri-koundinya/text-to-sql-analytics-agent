CREATE ROLE analytics_reader LOGIN PASSWORD 'analytics_reader' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO analytics_reader;

CREATE TABLE customers (
  customer_id SERIAL PRIMARY KEY,
  full_name VARCHAR(120) NOT NULL,
  city VARCHAR(80) NOT NULL,
  state VARCHAR(80) NOT NULL,
  signup_date DATE NOT NULL
);

CREATE TABLE products (
  product_id SERIAL PRIMARY KEY,
  product_name VARCHAR(160) NOT NULL,
  category VARCHAR(80) NOT NULL,
  unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE orders (
  order_id SERIAL PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
  order_date DATE NOT NULL,
  status VARCHAR(30) NOT NULL CHECK (status IN ('completed', 'cancelled', 'refunded'))
);

CREATE TABLE order_items (
  order_item_id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(order_id),
  product_id INTEGER NOT NULL REFERENCES products(product_id),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0)
);

INSERT INTO customers (full_name, city, state, signup_date) VALUES
  ('Aarav Sharma', 'Bengaluru', 'Karnataka', '2024-01-15'),
  ('Diya Patel', 'Mumbai', 'Maharashtra', '2024-02-09'),
  ('Kabir Singh', 'Delhi', 'Delhi', '2024-03-22'),
  ('Meera Iyer', 'Chennai', 'Tamil Nadu', '2024-04-11'),
  ('Rohan Gupta', 'Pune', 'Maharashtra', '2024-05-02');

INSERT INTO products (product_name, category, unit_price) VALUES
  ('Wireless Headphones', 'Electronics', 79.99),
  ('Mechanical Keyboard', 'Electronics', 119.00),
  ('Running Shoes', 'Sports', 89.50),
  ('Water Bottle', 'Sports', 18.00),
  ('Desk Lamp', 'Home', 42.75),
  ('Coffee Maker', 'Home', 65.00);

INSERT INTO orders (customer_id, order_date, status) VALUES
  (1, '2025-01-05', 'completed'), (2, '2025-01-11', 'completed'),
  (1, '2025-02-02', 'completed'), (3, '2025-02-17', 'cancelled'),
  (4, '2025-03-08', 'completed'), (2, '2025-03-19', 'refunded'),
  (5, '2025-04-01', 'completed'), (3, '2025-04-12', 'completed');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
  (1, 1, 1, 79.99), (1, 4, 2, 18.00), (2, 2, 1, 119.00),
  (3, 3, 1, 89.50), (3, 4, 1, 18.00), (4, 5, 1, 42.75),
  (5, 6, 1, 65.00), (5, 4, 3, 18.00), (6, 1, 1, 79.99),
  (7, 2, 1, 119.00), (7, 5, 2, 42.75), (8, 3, 2, 89.50);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM analytics_reader;
GRANT SELECT ON customers, products, orders, order_items TO analytics_reader;
