--Identify customers who have never rented films but have made payments
SELECT PAYMENT_DETAIL.CUSTOMER_ID
FROM PUBLIC.PAYMENT AS PAYMENT_DETAIL
LEFT JOIN   RENTAL AS RENTAL_DETAIL
ON PAYMENT_DETAIL.CUSTOMER_ID=RENTAL_DETAIL.CUSTOMER_ID
WHERE RENTAL_DETAIL.CUSTOMER_ID IS NULL ;
-- Determine the average number of films rented per customer, broken down by city.
SELECT
    city,
    ROUND(AVG(films_rented),2) AS average_films_rented
FROM (
    SELECT
        ct.city,
        c.customer_id,
        COUNT(r.rental_id) AS films_rented
    FROM
        customer c
    LEFT JOIN
        rental r ON c.customer_id = r.customer_id
    JOIN
        address a ON c.address_id = a.address_id
    JOIN
        city ct ON a.city_id = ct.city_id
    GROUP BY
        ct.city, c.customer_id
) AS customer_rental_counts
GROUP BY
    city;
	
-- Identify films that have been rented more than the average number of times and are currently not in inventory.
WITH CTE_NOT_IN_INVENTORY AS (
    SELECT FILM_INFO.FILM_ID
    FROM FILM FILM_INFO
    LEFT JOIN INVENTORY AS INVENTORY_DETAILS ON INVENTORY_DETAILS.FILM_ID = FILM_INFO.FILM_ID
    WHERE INVENTORY_DETAILS.FILM_ID IS NULL
),
CTE_HIGHER_THAN_AVERAGE AS (
    SELECT FILM_INFO.FILM_ID
    FROM FILM FILM_INFO
    LEFT JOIN INVENTORY INVENTORY_DETAILS ON FILM_INFO.FILM_ID = INVENTORY_DETAILS.FILM_ID
    LEFT JOIN RENTAL R ON R.INVENTORY_ID = INVENTORY_DETAILS.INVENTORY_ID
    GROUP BY FILM_INFO.FILM_ID
    HAVING COUNT(R.RENTAL_ID) > (
        SELECT AVG(RentalCount)
        FROM (
            SELECT COUNT(R.RENTAL_ID) AS RentalCount
            FROM FILM FILM_INFO
            LEFT JOIN INVENTORY INVENTORY_DETAILS ON FILM_INFO.FILM_ID = INVENTORY_DETAILS.FILM_ID
            LEFT JOIN RENTAL R ON R.INVENTORY_ID = INVENTORY_DETAILS.INVENTORY_ID
            GROUP BY FILM_INFO.FILM_ID
        ) AS Subquery
    )
)

SELECT DISTINCT C1.FILM_ID
FROM CTE_HIGHER_THAN_AVERAGE AS C1
 INNER JOIN CTE_NOT_IN_INVENTORY AS C2 ON C1.FILM_ID = C2.FILM_ID;

--Calculate the replacement cost of lost films for each store, considering the rental history.
-- I CONSIDERED HERE LOST FILMS AS FILMS THAT HAVE NO RETURN DATE 
SELECT
    STORE.STORE_ID,
    SUM(FILM_INFO.REPLACEMENT_COST) AS Total_Replacement_Cost
FROM
    STORE AS STORE
LEFT JOIN
    INVENTORY AS INVENTORY_DETAIL
ON
    STORE.STORE_ID = INVENTORY_DETAIL.STORE_ID
LEFT JOIN
    FILM AS FILM_INFO
ON
    FILM_INFO.FILM_ID = INVENTORY_DETAIL.FILM_ID
LEFT JOIN
    RENTAL AS RENTAL_INFO
ON
    INVENTORY_DETAIL.INVENTORY_ID = RENTAL_INFO.INVENTORY_ID
WHERE
    RENTAL_INFO.RETURN_DATE IS NULL
GROUP BY
    STORE.STORE_ID;
--
WITH RankedFilms AS (
    SELECT
        FILM_INFO.FILM_ID,
        FILM_INFO.TITLE AS Film_Title,
        FILM_CATEGORY.CATEGORY_ID,
        Category_info.NAME AS Category_Name,
        COUNT(RENTAL_INFO.RENTAL_ID) AS Rental_Count,
        SUM(Payment_details.AMOUNT) AS Total_Revenue,
        ROW_NUMBER() OVER (PARTITION BY  FILM_CATEGORY.CATEGORY_ID ORDER BY COUNT(Rental_info.RENTAL_ID) DESC) AS Rank
  FROM
        FILM AS FILM_INFO
  INNER JOIN
        FILM_CATEGORY 
    ON
        FILM_INFO.FILM_ID =  FILM_CATEGORY.FILM_ID
  INNER JOIN
        INVENTORY AS I
    ON
        FILM_INFO.FILM_ID = I.FILM_ID
  INNER JOIN
        RENTAL AS RENTAL_INFO
    ON
        I.INVENTORY_ID = RENTAL_INFO.INVENTORY_ID
  INNER JOIN
        PAYMENT AS Payment_details
    ON
        RENTAL_INFO.RENTAL_ID = Payment_details.RENTAL_ID
  INNER  JOIN
        CATEGORY AS Category_info
    ON
        FILM_CATEGORY.CATEGORY_ID = Category_info.CATEGORY_ID
   GROUP BY
        FILM_INFO.FILM_ID, FILM_INFO.TITLE, FILM_Category.CATEGORY_ID, Category_info.NAME
)
SELECT
    RankedFilms.Film_Title,
    RankedFilms.Category_Name,
    RankedFilms.Rental_Count,
    RankedFilms.Total_Revenue
FROM
    RankedFilms 
WHERE
    RankedFilms.Rank <= 5
ORDER BY
    Rankedfilms.Category_ID, Rankedfilms.Rank;
-- Develop a query that automatically updates the top 10 most frequently rented films.
ALTER TABLE FILM ADD COLUMN Rank INT;
CREATE OR REPLACE FUNCTION UpdateTop10RentedFilms() RETURNS Text AS $$
BEGIN
    -- Step 2: Update the FILM table based on the ranking.
    UPDATE FILM AS F
    SET Rank = TR.FilmRank
    FROM (
        SELECT
            F.FILM_ID,
            ROW_NUMBER() OVER (ORDER BY COUNT(R.RENTAL_ID) DESC) AS FilmRank
        FROM
            FILM AS F
        JOIN
            INVENTORY AS I
        ON
            F.FILM_ID = I.FILM_ID
        JOIN
            RENTAL AS R
        ON
            I.INVENTORY_ID = R.INVENTORY_ID
        GROUP BY
            F.FILM_ID
        LIMIT 10  -- Limit to the top 10 films
    ) AS TR
    WHERE
        F.FILM_ID = TR.FILM_ID;
END;
$$ LANGUAGE plpgsql;


SELECT UpdateTop10RentedFilms();



---Identify stores where the revenue from film rentals exceeds the revenue from payments for all customers.
SELECT
        inventory_details.store_id,
        SUM(film_info.rental_duration * film_info.rental_rate) AS rental_revenue,
        SUM(payment_details.amount) AS payment_revenue
    FROM
        public.inventory inventory_details
    INNER JOIN rental rental_details ON inventory_details.inventory_id = rental_details.inventory_id
    INNER JOIN film film_info ON inventory_details.film_id = film_info.film_id
    INNER JOIN payment payment_details ON rental_details.rental_id = payment_details.rental_id
    GROUP BY
        inventory_details.store_id;
----Determine the average rental duration and total revenue for each store

SELECT
    Store.store_id,
    AVG(EXTRACT(DAY FROM (rental_info.return_date - rental_info.rental_date))) AS average_rental_duration_days,
    SUM(payment_info.amount) AS total_revenue
FROM
    PUBLIC.store 
INNER JOIN
    staff staff_info ON store.store_id = staff_info.store_id
INNER JOIN
    customer customer_info ON staff_info.store_id = customer_info.store_id
INNER JOIN
    rental rental_info ON customer_info.customer_id = rental_info.customer_id
INNER JOIN
    payment payment_info ON rental_info.rental_id = payment_info.rental_id
GROUP BY
    store.store_id;
-----