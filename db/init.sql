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

-- Data is loaded by db/seed_large.sql (deterministic, setseed-based).

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_orders_status ON orders(status);

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM analytics_reader;
GRANT SELECT ON customers, products, orders, order_items TO analytics_reader;
