-- CUST_MONTH
WITH CUST_MONTH AS (
  SELECT DISTINCT 
    CUST_CODE,
    DATE_TRUNC(SHOP_DATE, MONTH) AS MY
  FROM `puri-crm.supermarket.supermarket`
  WHERE 
    CUST_CODE IS NOT NULL
  ORDER BY 
    CUST_CODE, MY
), 
-- CUST_LAG
CUST_LAG AS (
  SELECT 
    CUST_CODE,
    MY,
    DATE_SUB(MY, INTERVAL 1 MONTH) LAST_MY,
    LAG(MY) OVER(PARTITION BY CUST_CODE ORDER BY MY) LAG_MY,
    (SELECT MIN(MY) FROM CUST_MONTH WHERE CUST_CODE = CUST_CODE) MIN_MY,
  FROM CUST_MONTH
  ORDER BY 
    CUST_CODE, MY
), 
-- CUST_FLAG
CUST_FLAG AS (
  SELECT 
    *,
    1 this_month_flag,
    IF(LAG_MY IS NOT NULL AND
       LAG_MY = LAST_MY,
       1,0) last_month_flag,
    IF(LAG_MY IS NOT NULL AND 
       MIN_MY<LAST_MY,
       1,0) other_flag
  FROM CUST_LAG 
), 
-- CUST_MONTH_ALL
CUST_MONTH_ALL AS (
  SELECT
    *
  FROM 
    (SELECT DISTINCT CUST_CODE FROM `puri-crm.supermarket.supermarket` WHERE CUST_CODE IS NOT NULL)
  CROSS JOIN 
    (SELECT
      DISTINCT DATE_TRUNC(master_date,MONTH) AS MY
     FROM
      UNNEST(GENERATE_DATE_ARRAY(
        (SELECT MIN(SHOP_DATE) FROM `puri-crm.supermarket.supermarket`),
        (SELECT MAX(SHOP_DATE) FROM `puri-crm.supermarket.supermarket`), 
        INTERVAL 1 DAY)
      ) AS master_date )
), 
-- CUST_STATUS
CUST_STATUS AS (
  SELECT 
    A.*,
    B.* EXCEPT (CUST_CODE, MY),
    (SELECT MIN(MY) FROM CUST_MONTH WHERE CUST_CODE = A.CUST_CODE) MIN_MY_2,
    CASE 
      WHEN this_month_flag = 1 AND last_month_flag = 0 AND other_flag = 0 THEN 'New'
      WHEN this_month_flag = 1 AND last_month_flag = 1 THEN 'Repeat'
      WHEN this_month_flag = 1 AND last_month_flag = 0 AND other_flag = 1 THEN 'Reactivated'
      WHEN this_month_flag IS NULL AND (SELECT MIN(MY) FROM CUST_MONTH WHERE CUST_CODE = A.CUST_CODE) < A.MY THEN 'Churn'
    END AS STATUS
  FROM CUST_MONTH_ALL A
  LEFT JOIN CUST_FLAG B
  ON A.CUST_CODE = B.CUST_CODE 
  AND A.MY = B.MY
) 
-- FINAL VIEW
SELECT 
  MY,
  STATUS,
  IF( STATUS = "Churn", 
      -1*COUNT(DISTINCT CUST_CODE),
      COUNT(DISTINCT CUST_CODE)
  ) COUNT
FROM CUST_STATUS
WHERE STATUS IS NOT NULL
GROUP BY MY, STATUS