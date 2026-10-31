-- Users, roles, addresses, sellers.
-- Pattern used everywhere: generate_series(1, N) produces N rows, and
-- random() in the SELECT list is evaluated once per row.

CREATE TEMP TABLE seed_names AS
SELECT ARRAY['Aarav','Vivaan','Aditya','Vihaan','Arjun','Sai','Reyansh','Ayaan','Krishna','Ishaan',
             'Rohan','Kabir','Dev','Rahul','Karan','Nikhil','Siddharth','Manish','Varun','Yash',
             'Ananya','Diya','Aadhya','Saanvi','Pari','Anika','Navya','Myra','Sara','Ira',
             'Priya','Neha','Kavya','Meera','Riya','Pooja','Sneha','Tanvi','Isha','Zara'] AS first_names,
       ARRAY['Sharma','Verma','Iyer','Reddy','Nair','Patel','Gupta','Singh','Kumar','Das',
             'Mehta','Joshi','Rao','Menon','Chatterjee','Banerjee','Kapoor','Malhotra','Agarwal','Bose',
             'Pillai','Shetty','Kulkarni','Desai','Mishra','Pandey','Saxena','Khan','Fernandes','Thomas'] AS last_names;

CREATE TEMP TABLE seed_cities (city text, state text, pin_prefix text);
INSERT INTO seed_cities VALUES
 ('Bengaluru','Karnataka','560'), ('Mumbai','Maharashtra','400'), ('New Delhi','Delhi','110'),
 ('Hyderabad','Telangana','500'), ('Chennai','Tamil Nadu','600'), ('Kolkata','West Bengal','700'),
 ('Pune','Maharashtra','411'), ('Ahmedabad','Gujarat','380'), ('Jaipur','Rajasthan','302'),
 ('Lucknow','Uttar Pradesh','226'), ('Kochi','Kerala','682'), ('Chandigarh','Chandigarh','160'),
 ('Indore','Madhya Pradesh','452'), ('Bhubaneswar','Odisha','751'), ('Guwahati','Assam','781'),
 ('Mysuru','Karnataka','570'), ('Nagpur','Maharashtra','440'), ('Coimbatore','Tamil Nadu','641');

-- 5,000 users, created over the last ~2 years (user_id roughly follows signup time)
INSERT INTO core.users (email, full_name, phone, date_of_birth, status, is_prime, preferences, created_at, updated_at, last_login_at)
SELECT
    lower(first_name) || '.' || lower(last_name) || g || '@' || domain,
    CASE WHEN g % 97 = 0 THEN lower(first_name) || '  ' || upper(last_name)   -- a few messy names
         ELSE first_name || ' ' || last_name END,
    CASE WHEN r_phone < 0.85 THEN '+91' || (6000000000 + floor(random() * 3999999999))::bigint END,
    CASE WHEN r_dob < 0.80 THEN DATE '1960-01-01' + floor(random() * 16000)::int END,
    (CASE WHEN g % 333 = 0 THEN 'deleted' WHEN g % 50 = 0 THEN 'suspended' ELSE 'active' END)::core.user_status,
    random() < 0.20,
    jsonb_strip_nulls(jsonb_build_object(
        'language',   (ARRAY['en','en','en','hi','ta','te','bn','kn'])[1 + floor(random() * 8)::int],
        'newsletter', random() < 0.5,
        'theme',      CASE WHEN random() < 0.3 THEN 'dark' END,
        'notifications', jsonb_build_object('email', true, 'sms', random() < 0.4, 'push', random() < 0.7)
    )),
    created_at,
    created_at,
    CASE WHEN random() < 0.9 THEN created_at + random() * (now() - created_at) END
FROM (
    SELECT g,
           n.first_names[1 + floor(random() * 40)::int] AS first_name,
           n.last_names[1 + floor(random() * 30)::int]  AS last_name,
           (ARRAY['gmail.com','gmail.com','yahoo.com','outlook.com','shopsphere.test'])[1 + floor(random() * 5)::int] AS domain,
           random() AS r_phone,
           random() AS r_dob,
           now() - interval '730 days' + (g / 5000.0) * interval '725 days' + random() * interval '12 hours' AS created_at
    FROM generate_series(1, 5000) AS g
    CROSS JOIN seed_names n
) s
ORDER BY created_at;

-- ~20% of users were referred by an earlier user (self-referencing FK)
UPDATE core.users
SET referred_by = 1 + floor(random() * (user_id - 1))::bigint
WHERE user_id > 1 AND random() < 0.20;

-- Every user is a buyer; a few are admins / support agents
INSERT INTO core.user_roles (user_id, role_id, granted_at)
SELECT u.user_id, r.role_id, u.created_at
FROM core.users u JOIN core.roles r ON r.name = 'buyer';

INSERT INTO core.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM core.users u JOIN core.roles r ON (r.name = 'admin' AND u.user_id <= 3)
                                    OR (r.name = 'support' AND u.user_id BETWEEN 4 AND 15);

-- 1-3 addresses per user, exactly one marked default
INSERT INTO core.addresses (user_id, label, line1, line2, city, state, postal_code, is_default, created_at)
SELECT u.user_id,
       (ARRAY['home','work','other'])[n],
       (1 + floor(random() * 400))::int || ', ' || (ARRAY['MG Road','Park Street','Lake View','Station Road','Temple Street','Ring Road','Hill Crest','Main Bazaar'])[1 + floor(random() * 8)::int],
       CASE WHEN random() < 0.4 THEN 'Near ' || (ARRAY['City Mall','Metro Station','Central Park','Bus Stand'])[1 + floor(random() * 4)::int] END,
       c.city, c.state,
       c.pin_prefix || lpad(floor(random() * 1000)::int::text, 3, '0'),
       n = 1,
       u.created_at + n * interval '1 hour'
FROM core.users u
CROSS JOIN LATERAL generate_series(1, 1 + (u.user_id * 7 % 3)::int) AS n
JOIN seed_cities c ON c.city = (SELECT sc.city FROM seed_cities sc ORDER BY md5(sc.city || u.user_id || '-' || n) LIMIT 1);   -- sort key must depend on the candidate row!

-- 200 sellers: every 25th user owns a store
INSERT INTO core.sellers (owner_user_id, store_name, slug, gstin, commission_rate, is_verified, settings, joined_at)
SELECT u.user_id,
       store_name,
       lower(regexp_replace(store_name, '[^A-Za-z0-9]+', '-', 'g')),
       CASE WHEN random() < 0.9 THEN lpad((10 + u.user_id % 27)::text, 2, '0') || upper(substr(md5(u.user_id::text), 1, 10)) || '1Z' || (u.user_id % 10) END,
       (ARRAY[0.05, 0.08, 0.10, 0.10, 0.12, 0.15])[1 + floor(random() * 6)::int],
       random() < 0.75,
       jsonb_build_object(
           'return_window_days', (ARRAY[7, 10, 15, 30])[1 + floor(random() * 4)::int],
           'holiday_mode', random() < 0.05,
           'ships_from', (SELECT sc.city FROM seed_cities sc ORDER BY md5(sc.city || u.user_id) LIMIT 1),
           'support', jsonb_build_object('email', 'support@' || u.user_id || '.sellers.shopsphere.test', 'hours', '10:00-19:00')
       ),
       least(now(), u.created_at + random() * interval '30 days')
FROM (
    SELECT u.*, (ARRAY['Urban','Royal','Smart','Green','Happy','Prime','Tech','Desi','Classic','Modern'])[1 + floor(random() * 10)::int]
                || ' ' ||
                (ARRAY['Bazaar','Mart','Store','Hub','Corner','Depot','Emporium','Outlet','Studio','Traders'])[1 + floor(random() * 10)::int]
                || ' ' || u.user_id AS store_name
    FROM core.users u
    WHERE u.user_id % 25 = 0
) u
ORDER BY u.user_id;

INSERT INTO core.user_roles (user_id, role_id, granted_at)
SELECT s.owner_user_id, r.role_id, s.joined_at
FROM core.sellers s JOIN core.roles r ON r.name = 'seller';
