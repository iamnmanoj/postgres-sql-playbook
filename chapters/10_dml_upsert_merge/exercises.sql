-- =====================================================================
--  Chapter 10 · Exercises — UPDATE, DELETE, UPSERT, MERGE
--  Wrap everything that touches ShopSphere tables in BEGIN … ROLLBACK!
-- =====================================================================

-- [E10.01] (easy) Mark all notifications of user 8 as read now (only unread ones), returning how many.

-- [E10.02] (easy) Deactivate products that have no variants left active. Return their ids.

-- [E10.03] (medium) Using UPDATE … FROM, set every product's updated_at to the time of its most recent
--          price change (price_history), only where a price change exists.

-- [E10.04] (medium) Delete review_votes cast by suspended or deleted users (DELETE … USING).

-- [E10.05] (medium) Upsert a cart item for user 15: add variant 3 with quantity 1; if it is already in the
--          cart, increase the quantity by 1 but never above 10. (Create the cart first if missing.)

-- [E10.06] (hard) Recalculate review helpful_count from review_votes for all reviews where it is wrong,
--          returning the review_id and old/new values. (Hint: UPDATE … FROM with a subquery; old value via
--          a self-join in FROM.)

-- [E10.07] (hard) Write a MERGE that syncs playground_10.price_feed(sku, price) into catalog.products:
--          update base_price when different, ignore equal prices, and report each action with
--          merge_action(). Create the feed with 3 changed SKUs and 1 unknown SKU.
