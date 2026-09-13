# Comm-Log Send Reconciliation

Target: `target_base = 22` (Merchant 501, October 2026, Diwali campaigns)

## 1. Reconciliation Bridge

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | Naive count | 30 | Total rows in `communication_log` (starting point). |
| 1 | Filter merchant, date, and campaign type | 30 | Scoped to merchant 501, October 2026, and type '2' (all 30 rows already match). |
| 2 | Exclude unapproved campaigns | 26 | Campaign 9004 is `approval_awaiting`. Unapproved campaigns do not count toward official reporting. |
| 3 | Filter delivered sends (`delivery_status = 900`) | 22 | Excluded 4 soft failures (`delivery_status = 1100`: initial failed attempts for C2, C3, and D1). |
| 4 | *Investigative check: `COUNT(DISTINCT customer_id)`* | *21* | Global deduplication gave 21 instead of 22 because customer C20 was retargeted twice in standalone campaign 9101. |
| final | True target base | 22 | Standalone campaign 9101 counts each send event (7 sends), while retry chains deduplicate to reached customers (10 + 5 = 15). Total = 22. |

---

## 2. SQL Query

The queries can be run directly from `queries.sql` against `data/comm_log.db`.

```sql
SELECT COUNT(*) AS target_base
FROM communication_log l
JOIN campaign c ON l.communication_id = c.id
WHERE l.merchant_id = 501
  AND l.communication_type = '2'
  AND l.sent_time LIKE '2026-10%'
  AND c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND c.processing_status = 'processed'
  AND l.delivery_status = 900;
```

*(Note: For handling complex multi-level retry trees hierarchically, an alternative recursive CTE query is also provided in `queries.sql`.)*

---

## 3. Surprises in the Data

1. **Unapproved campaign sends were logged**: Campaign `9004` had 4 sends logged as delivered (`delivery_status = 900`), yet the campaign itself was still `approval_awaiting`. This showed that the delivery pipeline can run ahead of approval workflows, so filtering on campaign status is necessary.
2. **The C20 duplicate send in standalone campaign**: Customer `C20` was targeted twice in campaign `9101` (Oct 10 and Oct 20). If you naively run `COUNT(DISTINCT customer_id)` looking for distinct customers reached, you get 21 instead of 22. Understanding that standalone campaign sends are independent events, whereas retry chains deduplicate attempts, resolved the 1-count discrepancy.
