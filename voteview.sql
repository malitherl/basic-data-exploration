

/* 

Voteview Congressional Data Exploration 

Skills used: Joins, CTE's, Windows Functions, Aggregate Functions, Creating Views, Converting Data Types 

*/

-- Creating the tables

CREATE TABLE congress_terms(
    id BIGSERIAL PRIMARY KEY NOT NULL , 
    term INTEGER,	
    began DATE,
    ended DATE
);

COPY congress_terms(
    term, 
    began, 
    ended
) FROM 'C:\Users\Public\congress.csv' ENCODING 'utf8'
DELIMITER ','
CSV HEADER;


CREATE TABLE congress (
    id  BIGSERIAL PRIMARY KEY NOT NULL , 
    congress  INTEGER,	
    chamber  VARCHAR(25),
    icpsr  INTEGER, 
    state_icpsr	 INTEGER,
    district_code  INTEGER,	
    state_abbrev  VARCHAR(5),	
    party_code INTEGER, 	
    party_name	 VARCHAR(150),
    last_means INTEGER, 	
    bioname	 VARCHAR(50),
    born INTEGER, 
    died INTEGER,
    nominate_dim1 FLOAT, 	
    nominate_dim2 FLOAT, 
    nominate_number_of_votes INTEGER, 	
    nominate_number_of_errors INTEGER	
);

--Reading the .csv file with Postgres 
COPY congress(congress, 
              chamber, 
              icpsr, 
              state_icpsr, 
              district_code, 
              state_abbrev, 
              party_code, 
              party_name, 
              last_means, 
              bioname, 
              born, 
              died, 
              nominate_dim1, 
              nominate_dim2, 
              nominate_number_of_votes, 
              nominate_number_of_errors)
FROM 'C:\Users\Public\voteview.csv' ENCODING 'utf8'
DELIMITER ','
CSV HEADER;
--Changing client encoding for readibility 
SET client_encoding TO 'utf8';

/* Total number of progressive vs conservatives in congress by nominate score*
Still somewhat of a naive approach given that this is about the first dimension of the NOMINATE score, 
And the domain of this score pertains more to votes on economical issues vs social issues.  */

SELECT 
    DISTINCT congress,
    COUNT (CASE WHEN nominate_dim1 < 0 THEN 'progressive' END) OVER (PARTITION BY congress) AS progressive,
    COUNT (CASE WHEN nominate_dim1 >= 0 THEN 'conservative' END) OVER (PARTITION BY congress) AS conservative
    FROM congress 
    ORDER BY congress;
    
--And now we do the same to the second dimension of the NOMINATE score see how this distributes 
SELECT 
    DISTINCT congress,
    COUNT (CASE WHEN nominate_dim2 < 0 THEN 'progressive' END) OVER (PARTITION BY congress) AS progressive,
    COUNT (CASE WHEN nominate_dim2 >= 0 THEN 'conservative' END) OVER (PARTITION BY congress) AS conservative
    FROM congress 
    ORDER BY congress;

--We create a view to impose these results on top of each other in a visualization. 

CREATE VIEW prog_versus_cons AS 

WITH cte_div AS (
    SELECT congress, 
    COUNT (CASE WHEN nominate_dim2 < 0 THEN 'progressive' END) AS progressives, 
    COUNT (CASE WHEN nominate_dim2 >= 0 THEN 'conservative' END) AS conservatives, 
    COUNT(congress.congress) AS total
    FROM congress
    GROUP BY congress.congress 
)
SELECT
    congress,
    CAST(
        ((CAST(progressives AS float)/total)*100) AS NUMERIC(10,2)) 
        AS perc_l, 
    CAST(
        ((CAST(conservatives AS float)/total)*100) AS NUMERIC(10,2)) 
    AS perc_r
    FROM cte_div 
    ORDER BY congress;


SELECT 
    state_abbrev,
    AVG(nominate_dim1) AS nom_avg
FROM congress 
WHERE congress.congress > 70 
GROUP BY state_abbrev; 

SELECT 
    DISTINCT state_abbrev, 
    AVG(nominate_dim1) OVER (PARTITION BY state_abbrev) AS avg_state_nom1,
    AVG(nominate_dim2) OVER (PARTITION BY state_abbrev) AS avg_state_nom2
FROM 
    congress
ORDER BY avg_state_nom1, 3;




--Starting from the 71th Congress, this function looks for which congress members fall more much conservatively, but not only that, identifies how many of them there are in a given state
--In states where a congress member is not of the majority party, how much does this affect how they vote? Do they become even more conservative or more progressive? 

SELECT 
    state_abbrev, 
    COUNT(CASE WHEN nominate_dim1 > .5 THEN 'r' END) AS r , 
    AVG(nominate_dim1) AS avg
FROM congress
WHERE congress.congress > 70 AND nominate_dim1 > .5
GROUP BY state_abbrev
ORDER BY avg, r;

--Same as above but looking for the number of more progressive members of congress. 

SELECT 
    state_abbrev, 
    COUNT(CASE WHEN nominate_dim1 < -.5 THEN 'l' END) AS l , 
    AVG(nominate_dim1) AS avg
FROM congress
WHERE congress.congress > 70 AND nominate_dim1 < -.5
GROUP BY state_abbrev
ORDER BY avg, l;


--This is to get a view of where each state falls in terms of numbers of conservatives vs progressives 

SELECT state_abbrev, 
    COUNT (CASE WHEN nominate_dim1 < 0 THEN 'progressive' END) AS progressives, 
    COUNT (CASE WHEN nominate_dim1 >= 0 THEN 'conservative' END) AS conservatives, 
    AVG(nominate_dim1) AS nominate_history 
FROM congress
WHERE congress.congress > 70
GROUP BY state_abbrev;


CREATE VIEW nominate_dim1_by_state AS 
SELECT state_abbrev, 
    COUNT (CASE WHEN nominate_dim1 < 0 THEN 'progressive' END) AS progressives, 
    COUNT (CASE WHEN nominate_dim1 >= 0 THEN 'conservative' END) AS conservatives, 
    AVG(nominate_dim1) AS nominate_history 
FROM congress
WHERE congress.congress > 70
GROUP BY state_abbrev;


--This command calculates the average NOMINATE dimension 1 by Party 
--For our interests, we are looking at the Democratic and Republican parties from the 71st Congress onwards 



SELECT congress, party_name, AVG(nominate_dim1) AS dem_average 
FROM congress 
WHERE congress.congress > 70 AND party_name='Democrat '
GROUP BY congress.congress, party_name 
ORDER BY 1;

SELECT congress, party_name, AVG(nominate_dim1) AS repub_average 
FROM congress 
WHERE congress.congress > 70 AND party_name='Republican'
GROUP BY congress.congress, party_name 
ORDER BY 1;



/** This calculation, using Common Table Expressions, allows us to take a difference between these averages, 
    but not only that, we can with a join with the terms table chart these values by year as well as congressional term. 
**/


WITH cte_dems AS (
    SELECT congress, party_name, AVG(nominate_dim1) AS dem_average 
    FROM congress 
    WHERE congress.congress > 70 AND party_name='Democrat '
    GROUP BY congress.congress, party_name 
), cte_repubs AS (
    SELECT congress, party_name, AVG(nominate_dim1) AS repub_average 
    FROM congress 
    WHERE congress.congress > 70 AND party_name='Republican'
    GROUP BY congress.congress, party_name 
)

SELECT EXTRACT(YEAR FROM congress_terms.began) AS year, d.congress, ABS(ABS(d.dem_average)-ABS(r.repub_average)) AS average_difference 
FROM 
    cte_dems d 
    JOIN cte_repubs r 
        ON r.congress = d.congress
    JOIN congress_terms 
        ON congress_terms.term = d.congress
WHERE congress_terms.term > 70;
    

/**Another view for further visualizations **/    

CREATE VIEW party_averages_over_time AS 


WITH cte_dems AS (
    SELECT congress, party_name, AVG(nominate_dim1) AS dem_average 
    FROM congress 
    WHERE congress.congress > 70 AND party_name='Democrat '
    GROUP BY congress.congress, party_name 
), cte_repubs AS (
    SELECT congress, party_name, AVG(nominate_dim1) AS repub_average 
    FROM congress 
    WHERE congress.congress > 70 AND party_name='Republican'
    GROUP BY congress.congress, party_name 
)

SELECT EXTRACT(YEAR FROM congress_terms.began) AS year, d.congress, ABS(ABS(d.dem_average)-ABS(r.repub_average)) AS average_difference 
FROM 
    cte_dems d 
    JOIN cte_repubs r 
        ON r.congress = d.congress
    JOIN congress_terms 
        ON congress_terms.term = d.congress
WHERE congress_terms.term > 70; 