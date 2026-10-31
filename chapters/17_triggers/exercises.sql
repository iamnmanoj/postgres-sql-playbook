-- =====================================================================
--  Chapter 17 · Exercises — triggers
--  Name your trigger functions app.trg_ex17_* and drop demo triggers when done.
-- =====================================================================

-- [E17.01] (easy) Add a BEFORE UPDATE trigger on logistics.inventory that sets updated_at = now().
--          (Hint: you can reuse app.trg_set_updated_at.)

-- [E17.02] (medium) When a review is inserted or deleted, keep core.sellers.rating_avg up to date for the
--          product's seller (AFTER INSERT OR DELETE, FOR EACH ROW). Test inside BEGIN … ROLLBACK.

-- [E17.03] (medium) Prevent deleting a product that has ever been ordered: BEFORE DELETE trigger raising an
--          exception with a helpful message. Test it in a DO block.

-- [E17.04] (medium) Write a statement-level AFTER INSERT trigger with a transition table on sales.order_items that
--          RAISE NOTICEs how many items and how much revenue the statement inserted.

-- [E17.05] (hard) Write a trigger that, when a shipment's status changes to 'delivered', updates the order
--          status to 'delivered' (which in turn fires the status-history trigger from Q17.04). Verify both
--          effects inside BEGIN … ROLLBACK.
