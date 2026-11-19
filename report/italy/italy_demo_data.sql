-- Demo data for the Italy regional bubble map (report/italy/italy_region_bubble_map.jrxml).
-- Region ids are the FusionMaps 'Italy' entity keys; map_x/map_y are region centroids in the map's
-- base coordinate space (baseWidth 480 x baseHeight 560), derived from fusioncharts.italy.js outlines.
-- Re-runnable: drops and recreates both tables. Synthetic orders are seeded deterministically.
DROP TABLE IF EXISTS demo_italy_orders;
DROP TABLE IF EXISTS demo_italy_regions;
CREATE TABLE demo_italy_regions (region_id char(3) PRIMARY KEY, region text NOT NULL, short_code text, population integer NOT NULL, map_x numeric(6,1) NOT NULL, map_y numeric(6,1) NOT NULL);
INSERT INTO demo_italy_regions VALUES
('001','Abruzzo','AB',1270000,308.8,283.3),
('002','Basilicata','BA',530000,391.4,366.8),
('003','Calabria','CA',1840000,395.2,435.2),
('004','Campania','CM',5590000,346.3,348.2),
('005','Emilia-Romagna','EM',4450000,184.6,151.2),
('006','Friuli-Venezia Giulia','FI',1190000,270.0,61.0),
('007','Lazio','LA',5710000,266.5,294.4),
('008','Liguria','LI',1500000,89.1,167.7),
('009','Lombardia','LO',10000000,137.1,82.6),
('010','Marche','MA',1480000,276.6,222.4),
('011','Molise','MO',290000,334.6,307.5),
('012','Piemonte','PI',4250000,64.1,120.4),
('013','Puglia','PU',3900000,407.4,336.7),
('014','Sardegna','SA',1570000,79.8,388.9),
('015','Sicilia','SI',4790000,319.1,519.7),
('016','Toscana','TO',3660000,198.0,216.3),
('017','Trentino-Alto Adige','TR',1080000,203.9,41.7),
('018','Umbria','UM',850000,257.2,248.4),
('019','Valle d''Aosta','VA',123000,43.4,85.7),
('020','Veneto','VE',4850000,219.4,89.6),
('021','San Marino','SM',34000,258.6,193.3);
CREATE TABLE demo_italy_orders (order_id serial PRIMARY KEY, region_id char(3) NOT NULL REFERENCES demo_italy_regions(region_id), order_date date NOT NULL, channel text NOT NULL, amount numeric(10,2) NOT NULL);
SELECT setseed(0.42);
INSERT INTO demo_italy_orders (region_id, order_date, channel, amount)
SELECT r.region_id,
       DATE '2026-01-01' + (random() * 267)::int,
       (ARRAY['Online','Retail','Partner'])[1 + floor(random()*3)::int],
       round((40 + (random()^2) * 860)::numeric, 2)
FROM demo_italy_regions r
JOIN (VALUES ('001',0.8),('002',0.6),('003',0.5),('004',0.7),('005',1.5),('006',1.1),('007',1.3),('008',1.2),('009',1.6),('010',1.0),('011',0.6),('012',1.2),('013',0.7),('014',0.9),('015',0.6),('016',1.3),('017',1.5),('018',0.9),('019',1.7),('020',1.4),('021',0.9)) m(region_id, mult) ON m.region_id = r.region_id
CROSS JOIN LATERAL generate_series(1, greatest(8, round(r.population / 1000.0 * m.mult * 0.4)::int)) g;
CREATE INDEX ON demo_italy_orders (region_id);
ANALYZE demo_italy_orders;
