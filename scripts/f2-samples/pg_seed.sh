#!/bin/zsh
# Dựng dữ liệu máy chủ PostgreSQL thử `bipro-pg` (Docker, postgres:16-alpine, cổng 55432, CSDL `sales`, người dùng `bipro`).
# - VM-F7b (Phase F): public.sales (1 000 dòng của sales_2026.sqlite), public.customers (50), khung nhìn public.north_sales,
#   kho.ton_kho (3 dòng đủ kiểu; giá trị như Desktop nạp trong f7db-desktop.pbix).
# - VM-F15 (specs/011, US6): CSDL riêng `f15`, bảng public.types_f15 với timestamptz, time, interval, bytea, int[], text[] (có NULL, nhiều chiều).
# Tạo container (mật khẩu không ghi vào repo):
#   docker run -d --name bipro-pg -e POSTGRES_USER=bipro -e POSTGRES_PASSWORD=<mật khẩu> -e POSTGRES_DB=sales \
#     -e POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256" -p 55432:5432 postgres:16-alpine
# rồi: zsh scripts/f2-samples/pg_seed.sh
set -e
ROOT=${0:A:h:h:h}
DB=$ROOT/build/f-out/samples/sales_2026.sqlite
[ -f $DB ] || { echo "thiếu $DB (python3 scripts/f-samples/make_samples.py)" >&2; exit 1; }
{
cat <<'SQL'
DROP VIEW IF EXISTS public.north_sales;
DROP TABLE IF EXISTS public.sales, public.customers, public.types_f15;
DROP SCHEMA IF EXISTS kho CASCADE;
CREATE TABLE public.sales (orderid integer PRIMARY KEY, orderdate date, region text, customerid integer, product text, qty integer, price double precision, amount double precision);
CREATE TABLE public.customers (customerid integer PRIMARY KEY, name text, segment text);
SQL
echo "COPY public.sales FROM STDIN WITH (FORMAT csv);"
sqlite3 -csv $DB "select OrderID, OrderDate, Region, CustomerID, Product, Qty, Price, Amount from Sales order by OrderID"
echo '\.'
echo "COPY public.customers FROM STDIN WITH (FORMAT csv);"
sqlite3 -csv $DB "select CustomerID, Name, Segment from Customers order by CustomerID"
echo '\.'
cat <<'SQL'
CREATE VIEW public.north_sales AS SELECT * FROM public.sales WHERE region = 'North';
CREATE SCHEMA kho;
CREATE TABLE kho.ton_kho (id bigint PRIMARY KEY, sku text, con_hang boolean, so_luong integer, gia_von numeric(12,4),
  cap_nhat timestamp, ghi_chu varchar(200), ma uuid, thuoc_tinh jsonb);
INSERT INTO kho.ton_kho VALUES
  (1, 'SKU-001', true, 120, 15.5, '2026-03-01 08:30:00', 'Hàng mới', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', '{"mau": "do"}'),
  (2, 'SKU-002', false, 0, NULL, '2026-03-02 17:45:12.5', NULL, NULL, NULL),
  (3, 'SKU-003', NULL, NULL, 7.125, NULL, 'Ghi chú có dấu: Đà Nẵng', 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22', '[1, 2]');
SQL
} | docker exec -i bipro-pg psql -q -v ON_ERROR_STOP=1 -U bipro -d sales
docker exec bipro-pg psql -q -U bipro -d sales -c "DROP DATABASE IF EXISTS f15" -c "CREATE DATABASE f15"
docker exec -i bipro-pg psql -q -v ON_ERROR_STOP=1 -U bipro -d f15 <<'SQL'
CREATE TABLE public.types_f15 (id integer PRIMARY KEY, tz timestamptz, t time, iv interval, b bytea, ia integer[], ta text[]);
SET TIME ZONE 'UTC';
INSERT INTO public.types_f15 VALUES
  (1, '2026-03-01 08:30:00+07', '08:30:00', '1 day 02:03:04', '\x00ff10', '{1,2,3}', '{"a","b c"}'),
  (2, '2026-03-01 08:30:00.25-05', '23:59:59.5', '-2 hours -30 minutes', '\x', '{1,NULL,3}', '{NULL,"Đà Nẵng"}'),
  (3, '2026-12-31 23:00:00+00', '00:00:00', '1 mon 2 days', '\x48656c6c6f', '{{1,2},{3,4}}', '{{"x","y"},{"z","w"}}'),
  (4, NULL, NULL, NULL, NULL, NULL, NULL),
  (5, '1999-06-15 12:00:00+05:30', '12:34:56.789', '-1 year -2 mons 3 days', '\xdeadbeef', '{}', '{}'),
  (6, '2026-07-04 00:00:00+14', '17:00:00', '00:00:00.5', '\x22', '{-7}', '{"có \"ngoặc\"","x,y"}');
SQL
docker exec bipro-pg psql -U bipro -d sales -tAc "select (select count(*) from public.sales), (select count(*) from public.customers), (select count(*) from public.north_sales), (select count(*) from kho.ton_kho)"; docker exec bipro-pg psql -U bipro -d f15 -tAc 'select count(*) from public.types_f15'
