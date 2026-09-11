# Database optimization tree

The order in which this is usually applied
| Approach      | Description |
| ------------- | ------------- |
| Indexing      | the cheapest and most localized option. Always start here |
| Replication   | for when read volume is high, but write performance is still holding up |
| OLTP/OLAP separation | for when analytics start interfering with transactions |
| Denormalization      | for when JOINs and aggregations become too costly |
| CQRS          | for when read and write models have truly diverged |
| Sharding      | for when data volume or write load exceeds a single node's capacity |

In simple terms:

**Indexing** — a "book's table of contents." Fast to look things up, but every edit requires updating the index.

**Replication** — "copies of the book in different rooms." Everyone can read, but copies update with a delay.

**OLTP/OLAP** — "cash register vs. accounting." Cash register = fast operations; accounting = heavy reports. Don't mix them.

**Denormalization** — "keeping the answer ready instead of calculating it every time." Faster to read, harder to write.

**Sharding** — "splitting the book into volumes kept in different buildings." Scalable, but finding what you need is harder.

**CQRS** — "separate entrances for reading and writing." Each does its job well, but they need to be synchronized.

One rule
Go from top to bottom: index → ​​replica → separation → denormalization → CQRS → sharding.

Each subsequent step is more expensive than the last and harder to roll back.

## Simple Tree
```mermaid
flowchart TD
        A[0. Baseline & SLO<br/>Why: no optimization without metrics] --> B{Where is the bottleneck?}
        B -->|Query/Read| C[1. EXPLAIN ANALYZE<br/>Why: find actual plan and cardinality]
        B -->|Write/Locks| T[5. DBMS Tuning<br/>connection pool, vacuum, locks]
        B -->|Volume/Growth| P[8. Partitioning]
        B -->|Spikes/Analytics| Q[10. Asynchrony/CQRS/OLAP offload]
        C --> C1{What do we see?}
        C1 -->|Seq Scan| D[2. Indexes<br/>...]
        C1 -->|Inaccurate estimates| D0[ANALYZE, extended statistics]
        C1 -->|N+1| E[3. Rewrite queries<br/>...]
        C1 -->|Heavy JOINs/Aggregates| F[4. Denormalization/Materialized Views<br/>...]
        D --> G[Verification: latency, writes, plan]
        D0 --> G
        E --> G
        F --> G
        G --> H{Sufficient?}
        H -->|Yes| Z[Done]
        H -->|No| I[5. DBMS Tuning]
        I --> J[6. Caching]
        J --> K[7. Replicas/Read scaling]
        K --> L[8. Partitioning]
        L --> M[9. Sharding]
        M --> N[10. Asynchrony/CQRS/Archiving]
        N --> O[11. Verification and Rollback]
```

## Top-level tree

```mermaid
flowchart TD
        A["Problem: DB is slow / overloaded"] --> B{"What's the pain point?"}

        B -->|"Slow reads"| C["Indexing<br/>Purpose: fast search without full scans<br/>Cost: slows down writes, consumes space"]
        B -->|"Insufficient read capacity"| D["Replication<br/>Purpose: distribute reads across multiple nodes<br/>Cost: lag, eventual consistency"]
        B -->|"Mixed analytics and transactions"| E["OLTP / OLAP separation<br/>Purpose: analytics don't interfere with transactions<br/>Cost: separate infrastructure, ETL"]
        B -->|"Expensive JOINs and aggregates"| F["Denormalization<br/>Purpose: eliminate JOINs, read pre-computed data<br/>Cost: data duplication, complex writes"]
        B -->|"Capacity / write limits exceeded"| G["Sharding<br/>Purpose: horizontally scale writes and storage<br/>Cost: complexity, cross-shard queries"]
        B -->|"Divergent read and write patterns"| H["CQRS<br/>Purpose: separate write model and read model<br/>Cost: synchronization, eventual consistency"]

        C --> C1["B-tree — standard comparisons and sorting"]
        C --> C2["Composite — multiple columns in a single index"]
        C --> C3["Partial / covering — only the necessary subset"]
        C --> C4["GIN / GiST / BRIN — JSON, search, geo, time-series"]

        D --> D1["Read replicas — scaling reads"]
        D --> D2["Read/write split — application knows where to direct requests"]
        D --> D3["Lag — application must tolerate latency"]

        E --> E1["OLTP — fast, short transactions"]
        E --> E2["OLAP — heavy analytics on a separate store"]
        E --> E3["ETL / CDC — data transfer between them"]

        F --> F1["Materialized view — precomputed result"]
        F --> F2["Column duplication — fewer JOINs"]
        F --> F3["Precomputed counts — avoid on-the-fly calculation"]

        G --> G1["Shard key — how data is partitioned"]
        G --> G2["Routing — how the application finds the right shard"]
        G --> G3["Cross-shard — the most expensive operation"]

        H --> H1["Write model — normalized, strict"]
        H --> H2["Read model — denormalized, fast"]
        H --> H3["Synchronization — events, queues, outbox"]
```


## Detailed Tree

```mermaid
flowchart TD
        A["0. Baseline & SLO<br/>p95/p99, throughput, slow log, wait events, locks, lag<br/>Why: optimization without metrics is guesswork"] --> B{"Where is the main bottleneck?"}

        B -->|"Query/Read"| C["1. EXPLAIN (ANALYZE, BUFFERS)<br/>actual plan, estimated vs actual, loops, spill<br/>Why: squeeze performance out of the query layer first"]
        C --> C1{"What do we see?"}
        C1 -->|"Seq Scan / missing index"| D["2. Indexes<br/>B-tree, composite, covering, partial, GIN/GiST/BRIN<br/>Why: less I/O and CPU for reads. Cost: writes, storage, vacuum"]
        C1 -->|"Inaccurate cardinality estimate"| D0["ANALYZE, extended statistics, histograms<br/>Why: the planner chooses a poor plan"]
        C1 -->|"N+1 / inefficient access"| E["3. Rewrite queries<br/>keyset pagination, batching, avoid SELECT *, avoid functions on columns<br/>Why: cheaper and more reversible than schema changes"]
        C1 -->|"Heavy JOINs/aggregates"| F["4. Denormalization/materialization<br/>matview, summary, CQRS read model, JSONB<br/>Why: eliminates expensive JOINs/aggregates. Cost: writes, invalidation, eventual consistency"]

        D --> G["Verification: latency, plan, writes, vacuum, bloat"]
        D0 --> G
        E --> G
        F --> G
        G --> H{"Sufficient?"}
        H -->|"Yes"| Z["Done. Lock in baseline and alerts"]
        H -->|"No"| I["5. DBMS and instance tuning<br/>connection pool, shared_buffers, work_mem, autovacuum, WAL, locks<br/>Why: bottlenecks are often connections, memory, vacuum, checkpoint"]

        B -->|"Writes/locks"| I
        B -->|"Volume/growth"| P["8. Partitioning<br/>range/list/hash, pruning, local indexes, retention<br/>Why: smaller indexes, faster vacuum, easier archiving; still a single cluster"]
        B -->|"Spikes/analytics"| Q["10. Asynchrony/CQRS/OLAP offload<br/>outbox, Kafka, batch, read model, S3/ClickHouse<br/>Why: smooths out spikes, offloads OLTP"]

        I --> J["6. Caching<br/>local, Redis/Memcached, CDN, TTL, versioning, stampede protection<br/>Why: reduces read load and latency. Cost: stale data, invalidation, infrastructure"]
        J --> K["7. Replication and read scaling<br/>read replicas, read/write split, lag awareness, read-your-writes<br/>Why: scales reads, not writes; complicates consistency"]
        K --> L["8. Partitioning<br/>range/list/hash, pruning, local indexes, retention<br/>Why: reduces index size and speeds up vacuum; does not scale writes across nodes"]
        L --> M["9. Sharding<br/>shard key, routing, cross-shard, 2PC/Saga, rebalancing, hot shards<br/>Why: scales writes and volume. Cost: immense complexity. Only after exhausting previous steps"]
        M --> N["10. Asynchrony/CQRS/archiving<br/>outbox, Kafka, CQRS, TTL, S3, ClickHouse<br/>Why: smooths out spikes, offloads OLTP, separates analytics"]
        N --> O["11. Verification and rollback<br/>load testing, canary, feature flags, monitoring, rollback plan<br/>Why: optimization can improve one thing while worsening another"]
        O --> Z

        P --> L
        Q --> N
```