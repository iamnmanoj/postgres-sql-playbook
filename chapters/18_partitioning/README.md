# Chapter 18 · Table partitioning

[← Previous](../17_triggers/README.md) · [Index](../../README.md) · [Next →](../19_security_rls/README.md)

## What you'll learn
- What declarative partitioning is and when it pays off
- RANGE, LIST and HASH partitioning, plus sub-partitioning
- Partition pruning at plan time and at run time
- Managing partitions: create ahead, the DEFAULT partition, ATTACH, DETACH (CONCURRENTLY), dropping for retention
- Keys, indexes and row movement on partitioned tables
- Partition-wise aggregation, and the legacy `INHERITS` mechanism

## Concepts

### Why partition?
A partitioned table is a **parent with no storage** plus **child tables** (partitions), each holding a slice of the rows chosen by the **partition key**.
- **Pruning**: queries that filter on the key only touch matching partitions (Q18.03).
- **Cheap retention**: `DROP TABLE old_partition` is instant, while `DELETE` of millions of rows bloats the table (Q18.14).
- **Maintenance per partition**: `VACUUM`, indexes and bulk loads work on smaller pieces.

It helps when tables are **large** (tens of GB, hundreds of millions of rows) and queries filter on the key. For small tables it only adds planning overhead.
In ShopSphere, `analytics.events` is partitioned by month. See [schema.sql](../01_ddl_schema/schema.sql) and the dynamic partition creation in the seed.

### Strategies
| Strategy | Syntax | Typical key |
|---|---|---|
| RANGE | `PARTITION BY RANGE (occurred_at)` / `FOR VALUES FROM (a) TO (b)` (upper bound exclusive) | time |
| LIST | `PARTITION BY LIST (region)` / `FOR VALUES IN ('south', 'west')` | category, tenant, region |
| HASH | `PARTITION BY HASH (user_id)` / `FOR VALUES WITH (MODULUS 4, REMAINDER 0)` | even spread with no natural range |
| DEFAULT | `PARTITION OF t DEFAULT` | everything that matches no other partition, including NULL range keys |

Partitions can be partitioned again (sub-partitioning, Q18.09).

### Rules to remember
- **Primary keys and unique constraints must include the partition key** (Q18.10). That's why `analytics.events` has `PRIMARY KEY (event_id, occurred_at)`.
- An index created on the parent is created on every partition automatically, including future ones.
- Updating the key **moves** the row to the right partition (Q18.11).
- Creating a partition fails if the DEFAULT partition already has rows for its range (Q18.06), so create partitions *ahead of time* (Q18.05). Tools such as `pg_partman` automate this.
- `ATTACH PARTITION` scans the table to validate the bounds unless a matching `CHECK` constraint already exists (Q18.13).
- `DETACH PARTITION … CONCURRENTLY` (PG14) avoids blocking queries.

### Pruning
- **Plan-time pruning**: the planner removes partitions when the filter can be evaluated up front.
- **Run-time pruning**: for parameters and `now()`, partitions are removed at execution time, shown as `Subplans Removed: N` (Q18.04).

## Keywords & functions

| Keyword / function | What it does | Query IDs |
|---|---|---|
| `PARTITION BY RANGE`, `pg_partition_tree()`, `pg_get_partkeydef()`, `relpartbound` | inspect a partitioned table | Q18.01 |
| `tableoid::regclass` | which partition a row is in | Q18.02 |
| partition pruning | skip irrelevant partitions | Q18.03 |
| run-time pruning, `PREPARE`/`EXECUTE`, `plan_cache_mode` | prune with parameters | Q18.04 |
| `CREATE TABLE … PARTITION OF … FOR VALUES FROM … TO` | add a range partition | Q18.05 |
| `DEFAULT` partition | catch-all | Q18.06 |
| `PARTITION BY LIST`, `FOR VALUES IN` | list partitioning | Q18.07 |
| `PARTITION BY HASH`, `MODULUS`, `REMAINDER` | hash partitioning | Q18.08 |
| sub-partitioning | multi-level | Q18.09 |
| partitioned index, PK must include the key | keys and indexes | Q18.10 |
| row movement | UPDATE of the key | Q18.11 |
| `pg_partition_root()`, `pg_partition_ancestors()` | navigate the hierarchy | Q18.12 |
| `ATTACH PARTITION` + `CHECK` | plug in a loaded table | Q18.13 |
| `DETACH PARTITION [CONCURRENTLY]`, `DROP TABLE` | retention | Q18.14 |
| partition sizes and row counts | retention candidates | Q18.15 |
| `enable_partitionwise_aggregate` / `_join` | per-partition execution | Q18.16 |
| `INHERITS`, `ONLY` | legacy table inheritance | Q18.17 |

## Gotchas
- Queries **without** the partition key in `WHERE` scan every partition (31 here).
- Thousands of partitions slow planning down. Monthly or weekly partitions are usually plenty.
- Foreign keys **referencing** a partitioned table need the full key, including the partition column.
- Global unique constraints that don't include the partition key aren't possible.
- Rows inserted for a range with no partition and no DEFAULT fail with "no partition of relation found for row".

## Run it
```bash
scripts/psql.sh -e -f /playbook/chapters/18_partitioning/queries.sql
```
Then try [exercises.sql](exercises.sql) and check your work against [solutions.sql](solutions.sql).
