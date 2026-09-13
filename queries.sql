-- Step 0: Naive count
SELECT COUNT(*) FROM communication_log;

-- Step 1: Scope to merchant 501, October 2026, campaign communications
SELECT COUNT(*) 
FROM communication_log
WHERE merchant_id = 501
  AND communication_type = '2'
  AND sent_time LIKE '2026-10%';

-- Step 2: Exclude unapproved campaigns (drops 4 rows from campaign 9004)
SELECT COUNT(*) 
FROM communication_log l
JOIN campaign c ON l.communication_id = c.id
WHERE l.merchant_id = 501
  AND l.communication_type = '2'
  AND l.sent_time LIKE '2026-10%'
  AND c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND c.processing_status = 'processed';

-- Step 3: Filter for delivered sends only (drops 4 soft failures with status 1100)
SELECT COUNT(*) 
FROM communication_log l
JOIN campaign c ON l.communication_id = c.id
WHERE l.merchant_id = 501
  AND l.communication_type = '2'
  AND l.sent_time LIKE '2026-10%'
  AND c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND c.processing_status = 'processed'
  AND l.delivery_status = 900;

-- Step 4: Investigating global distinct customer count (returns 21 instead of 22)
SELECT COUNT(DISTINCT l.customer_id) 
FROM communication_log l
JOIN campaign c ON l.communication_id = c.id
WHERE l.merchant_id = 501
  AND l.communication_type = '2'
  AND l.sent_time LIKE '2026-10%'
  AND c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND c.processing_status = 'processed'
  AND l.delivery_status = 900;

-- Final Query: Computes target_base (22)
SELECT COUNT(*) AS target_base
FROM communication_log l
JOIN campaign c ON l.communication_id = c.id
WHERE l.merchant_id = 501
  AND l.communication_type = '2'
  AND l.sent_time LIKE '2026-10%'
  AND c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND c.processing_status = 'processed'
  AND l.delivery_status = 900;

-- Alternative: Recursive CTE modeling retry chains vs standalone campaigns
WITH RECURSIVE campaign_tree AS (
    SELECT id AS campaign_id, id AS root_campaign_id
    FROM campaign
    WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id AS campaign_id, ct.root_campaign_id
    FROM campaign c
    JOIN campaign_tree ct ON c.parent_id = ct.campaign_id
),
eligible_sends AS (
    SELECT 
        l.customer_id,
        ct.root_campaign_id,
        CASE 
            WHEN c.parent_id IS NULL AND NOT EXISTS (SELECT 1 FROM campaign child WHERE child.parent_id = c.id)
            THEN 1 ELSE 0 
        END AS is_standalone
    FROM communication_log l
    JOIN campaign c ON l.communication_id = c.id
    JOIN campaign_tree ct ON c.id = ct.campaign_id
    WHERE l.merchant_id = 501
      AND l.communication_type = '2'
      AND l.sent_time LIKE '2026-10%'
      AND c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND c.processing_status = 'processed'
      AND l.delivery_status = 900
)
SELECT 
    (SELECT COUNT(*) FROM eligible_sends WHERE is_standalone = 1)
    +
    (SELECT COUNT(*) FROM (SELECT DISTINCT root_campaign_id, customer_id FROM eligible_sends WHERE is_standalone = 0))
    AS target_base;
