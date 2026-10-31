-- Lookup / reference data: roles, warehouses, brands, the category tree.
-- TEMP tables hold generator config and disappear when the session ends.

INSERT INTO core.roles (name) VALUES ('buyer'), ('seller'), ('admin'), ('support');

INSERT INTO logistics.warehouses (code, city, state, capacity, opened_on) VALUES
    ('BLR1', 'Bengaluru', 'Karnataka',     120000, '2019-04-01'),
    ('MUM1', 'Mumbai',    'Maharashtra',   150000, '2018-11-15'),
    ('DEL1', 'New Delhi', 'Delhi',         140000, '2018-07-01'),
    ('HYD1', 'Hyderabad', 'Telangana',      90000, '2020-02-10'),
    ('CHN1', 'Chennai',   'Tamil Nadu',     80000, '2020-09-01'),
    ('KOL1', 'Kolkata',   'West Bengal',    70000, '2021-01-20'),
    ('PUN1', 'Pune',      'Maharashtra',    60000, '2022-06-05'),
    ('AMD1', 'Ahmedabad', 'Gujarat',        50000, '2023-03-12');

-- "kind" drives names, features, attributes and variants of generated products
CREATE TEMP TABLE seed_kind (
    kind      text PRIMARY KEY,
    features  text[],
    uses      text[],
    colors    text[],
    brand_ids int[]
);
INSERT INTO seed_kind (kind, features, uses, colors) VALUES
 ('electronics', ARRAY['fast charging','long battery life','AMOLED display','active noise cancellation','wireless connectivity','Bluetooth 5.3','water resistance','dual cameras','lightweight aluminium body','smart assistant support'],
                 ARRAY['work from home','gaming','travel','streaming','students'], ARRAY['black','silver','blue','white','graphite']),
 ('fashion',     ARRAY['breathable cotton','slim fit','stretchable denim','premium leather','memory foam insole','machine washable','all-day comfort','handcrafted stitching'],
                 ARRAY['office wear','weekends','parties','festive season','daily wear'], ARRAY['black','navy','white','olive','maroon','beige']),
 ('home',        ARRAY['stainless steel body','energy efficient motor','non-stick coating','ergonomic design','solid wood finish','easy to clean','compact footprint','5-year warranty'],
                 ARRAY['small kitchens','modern homes','home offices','gifting','daily cooking'], ARRAY['black','white','walnut','grey','red']),
 ('books',       ARRAY['gripping storytelling','award-winning author','beautiful illustrations','practical exercises','bestselling series','thought-provoking ideas'],
                 ARRAY['weekend reading','exam preparation','bedtime stories','book clubs','gifting'], ARRAY['multicolor']),
 ('sports',      ARRAY['anti-slip grip','durable build','lightweight frame','sweat resistant','adjustable size','weatherproof material'],
                 ARRAY['home workouts','trekking','cycling trips','gym sessions','outdoor adventures'], ARRAY['black','red','green','orange','blue']),
 ('beauty',      ARRAY['natural ingredients','dermatologically tested','paraben free','long lasting','suitable for all skin types','vitamin C'],
                 ARRAY['daily skincare','dry skin','oily skin','hair fall control','glowing skin'], ARRAY['none']),
 ('toys',        ARRAY['educational fun','safe non-toxic material','ages 6 and up','develops problem solving','family friendly'],
                 ARRAY['family game night','birthday gifts','STEM learning','rainy days'], ARRAY['multicolor','red','yellow']);

-- Fictional brands (kind = which product family they make)
CREATE TEMP TABLE seed_brands (name text, kind text, country_code char(2), founded_year smallint);
INSERT INTO seed_brands VALUES
 ('Voltix','electronics','IN',2012), ('Auralux','electronics','US',2004), ('Pixelon','electronics','KR',1998),
 ('Nimbus','electronics','CN',2015), ('Zentro','electronics','TW',2009), ('Lumora','electronics','JP',1987),
 ('Quantra','electronics','IN',2018), ('Sonique','electronics','DE',1995),
 ('Urbanloom','fashion','IN',2011), ('Swiftwear','fashion','US',2001), ('Kraftly','fashion','IN',2016),
 ('Velvetta','fashion','IT',1979), ('Denimora','fashion','IN',2008), ('Stridex','fashion','VN',2013),
 ('Bloomkin','fashion','IN',2019),
 ('Cookwise','home','IN',2005), ('Hearthly','home','SE',1990), ('Ironleaf','home','IN',2014),
 ('Nestora','home','DK',2002), ('Brewmaster','home','IN',2017),
 ('Northpeak','sports','US',1996), ('Flexon','sports','IN',2015), ('Trailblaze','sports','CA',2007),
 ('Glowveda','beauty','IN',2016), ('Purelle','beauty','FR',1989), ('Mintique','beauty','IN',2020),
 ('Brainbox','toys','IN',2012), ('Playtopia','toys','GB',1999), ('Tinkerly','toys','IN',2021),
 ('Orbitron','electronics','US',2022);   -- a brand with no products (useful for outer-join demos)

INSERT INTO catalog.brands (name, country_code, founded_year)
SELECT name, country_code, founded_year FROM seed_brands ORDER BY kind, name;

UPDATE seed_kind k
SET brand_ids = (SELECT array_agg(b.brand_id ORDER BY b.brand_id)
                 FROM catalog.brands b JOIN seed_brands sb USING (name)
                 WHERE sb.kind = k.kind AND sb.name <> 'Orbitron');

-- Category tree (up to 3 levels). Leaves with a kind receive products.
CREATE TEMP TABLE seed_categories (
    slug text, parent_slug text, name text, sort_order smallint,
    kind text, nouns text[], min_price numeric, max_price numeric
);
INSERT INTO seed_categories VALUES
 ('electronics', NULL, 'Electronics', 1, NULL, NULL, NULL, NULL),
 ('mobiles-tablets', 'electronics', 'Mobiles & Tablets', 1, NULL, NULL, NULL, NULL),
 ('smartphones', 'mobiles-tablets', 'Smartphones', 1, 'electronics', ARRAY['Smartphone','5G Phone','Camera Phone'], 7999, 89999),
 ('tablets', 'mobiles-tablets', 'Tablets', 2, 'electronics', ARRAY['Tablet','Drawing Tablet','Kids Tablet'], 9999, 69999),
 ('mobile-accessories', 'mobiles-tablets', 'Mobile Accessories', 3, 'electronics', ARRAY['Power Bank','Fast Charger','Phone Case','USB-C Cable'], 199, 2999),
 ('computers', 'electronics', 'Computers', 2, NULL, NULL, NULL, NULL),
 ('laptops', 'computers', 'Laptops', 1, 'electronics', ARRAY['Laptop','Gaming Laptop','Ultrabook'], 29999, 189999),
 ('monitors', 'computers', 'Monitors', 2, 'electronics', ARRAY['Monitor','Curved Monitor','4K Monitor'], 6999, 59999),
 ('keyboards-mice', 'computers', 'Keyboards & Mice', 3, 'electronics', ARRAY['Mechanical Keyboard','Wireless Mouse','Gaming Mouse'], 499, 9999),
 ('audio', 'electronics', 'Audio', 3, NULL, NULL, NULL, NULL),
 ('headphones', 'audio', 'Headphones & Earbuds', 1, 'electronics', ARRAY['Headphones','Wireless Earbuds','Neckband'], 799, 29999),
 ('speakers', 'audio', 'Speakers', 2, 'electronics', ARRAY['Bluetooth Speaker','Soundbar','Party Speaker'], 999, 39999),
 ('cameras', 'electronics', 'Cameras', 4, 'electronics', ARRAY['Mirrorless Camera','Action Camera','DSLR Camera'], 14999, 149999),
 ('wearables', 'electronics', 'Wearables', 5, NULL, NULL, NULL, NULL),
 ('smartwatches', 'wearables', 'Smartwatches', 1, NULL, NULL, NULL, NULL),          -- intentionally empty
 ('fashion', NULL, 'Fashion', 2, NULL, NULL, NULL, NULL),
 ('men', 'fashion', 'Men', 1, NULL, NULL, NULL, NULL),
 ('mens-tshirts', 'men', 'T-Shirts & Polos', 1, 'fashion', ARRAY['T-Shirt','Polo T-Shirt','Henley'], 299, 1999),
 ('mens-jeans', 'men', 'Jeans', 2, 'fashion', ARRAY['Slim Jeans','Straight Jeans','Cargo Jeans'], 799, 3999),
 ('mens-shoes', 'men', 'Shoes', 3, 'fashion', ARRAY['Sneakers','Running Shoes','Loafers'], 999, 8999),
 ('women', 'fashion', 'Women', 2, NULL, NULL, NULL, NULL),
 ('womens-dresses', 'women', 'Dresses', 1, 'fashion', ARRAY['Maxi Dress','Wrap Dress','Kurta Set'], 599, 4999),
 ('womens-handbags', 'women', 'Handbags', 2, 'fashion', ARRAY['Tote Bag','Sling Bag','Clutch'], 699, 7999),
 ('womens-footwear', 'women', 'Footwear', 3, 'fashion', ARRAY['Heels','Flats','Sandals'], 499, 4999),
 ('kids-clothing', 'fashion', 'Kids Clothing', 3, 'fashion', ARRAY['Kids T-Shirt','Frock','Romper'], 199, 1499),
 ('home-kitchen', NULL, 'Home & Kitchen', 3, NULL, NULL, NULL, NULL),
 ('kitchen-appliances', 'home-kitchen', 'Kitchen Appliances', 1, 'home', ARRAY['Mixer Grinder','Air Fryer','Electric Kettle','Induction Cooktop'], 999, 14999),
 ('cookware', 'home-kitchen', 'Cookware', 2, 'home', ARRAY['Non-stick Pan','Pressure Cooker','Kadai'], 399, 4999),
 ('furniture', 'home-kitchen', 'Furniture', 3, 'home', ARRAY['Office Chair','Bookshelf','Study Table'], 2499, 34999),
 ('home-decor', 'home-kitchen', 'Home Decor', 4, 'home', ARRAY['Wall Clock','Table Lamp','Cushion Cover'], 199, 3999),
 ('books', NULL, 'Books', 4, NULL, NULL, NULL, NULL),
 ('fiction', 'books', 'Fiction', 1, 'books', ARRAY['River','Empire','Secret','Journey','Garden','Storm'], 149, 899),
 ('non-fiction', 'books', 'Non-Fiction', 2, 'books', ARRAY['Habits','Money','Mind','History','Leadership'], 199, 1299),
 ('childrens-books', 'books', 'Children''s Books', 3, 'books', ARRAY['Dragon','Forest','Rocket','Puppy'], 99, 599),
 ('sports-fitness', NULL, 'Sports & Fitness', 5, NULL, NULL, NULL, NULL),
 ('fitness', 'sports-fitness', 'Fitness Equipment', 1, 'sports', ARRAY['Yoga Mat','Dumbbell Set','Resistance Band'], 299, 9999),
 ('cycling', 'sports-fitness', 'Cycling', 2, 'sports', ARRAY['Mountain Bike','Cycling Helmet','Bike Light'], 499, 39999),
 ('outdoor', 'sports-fitness', 'Outdoor & Trekking', 3, 'sports', ARRAY['Camping Tent','Trekking Backpack','Trekking Pole'], 499, 14999),
 ('beauty', NULL, 'Beauty & Personal Care', 6, NULL, NULL, NULL, NULL),
 ('skincare', 'beauty', 'Skincare', 1, 'beauty', ARRAY['Face Serum','Sunscreen SPF 50','Moisturizer'], 199, 2499),
 ('haircare', 'beauty', 'Haircare', 2, 'beauty', ARRAY['Shampoo','Hair Oil','Hair Dryer'], 149, 4999),
 ('toys-games', NULL, 'Toys & Games', 7, NULL, NULL, NULL, NULL),
 ('board-games', 'toys-games', 'Board Games & Puzzles', 1, 'toys', ARRAY['Board Game','Jigsaw Puzzle','Card Game'], 299, 2999),
 ('stem-toys', 'toys-games', 'STEM Toys', 2, 'toys', ARRAY['Robot Kit','Building Blocks','Science Kit'], 499, 6999);

-- Insert level by level: each pass adds children whose parent already exists
DO $$
BEGIN
    LOOP
        INSERT INTO catalog.categories (parent_id, name, slug, sort_order)
        SELECT p.category_id, s.name, s.slug, s.sort_order
        FROM seed_categories s
        LEFT JOIN catalog.categories p ON p.slug = s.parent_slug
        WHERE (s.parent_slug IS NULL OR p.category_id IS NOT NULL)
          AND NOT EXISTS (SELECT 1 FROM catalog.categories c WHERE c.slug = s.slug)
        ORDER BY s.parent_slug NULLS FIRST, s.sort_order;
        EXIT WHEN NOT FOUND;
    END LOOP;
END $$;

-- Leaf categories that receive products, numbered 1..N for random picking
CREATE TEMP TABLE seed_leaf AS
SELECT c.category_id, s.kind, s.nouns, s.min_price, s.max_price,
       row_number() OVER (ORDER BY c.category_id)::int AS rn
FROM seed_categories s
JOIN catalog.categories c USING (slug)
WHERE s.kind IS NOT NULL;
