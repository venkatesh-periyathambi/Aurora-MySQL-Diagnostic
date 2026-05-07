-- ============================================================================
-- Aurora MySQL Test Setup: Schema, Data, and Indexes
-- Simulates a retail planning data warehouse with 1M+ fact rows
-- ============================================================================
-- WARNING: This script DROPS and recreates the 'qldwh' database.
-- DO NOT run on production. For test/dev environments only.
-- ============================================================================

DROP DATABASE IF EXISTS qldwh;
CREATE DATABASE qldwh;
USE qldwh;

-- ============================================================================
-- DIMENSION TABLES
-- ============================================================================

CREATE TABLE dim_items (
    dim_item_id INT NOT NULL AUTO_INCREMENT,
    item_code VARCHAR(20) NOT NULL,
    item_name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    subcategory VARCHAR(50),
    brand VARCHAR(50),
    color VARCHAR(30),
    size VARCHAR(10),
    unit_cost DECIMAL(10,2),
    unit_price DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (dim_item_id),
    INDEX idx_item_code (item_code),
    INDEX idx_category (category, subcategory)
) ENGINE=InnoDB;

CREATE TABLE dim_stores (
    dim_store_id INT NOT NULL AUTO_INCREMENT,
    store_code VARCHAR(20) NOT NULL,
    store_name VARCHAR(100) NOT NULL,
    region VARCHAR(50),
    country VARCHAR(50),
    city VARCHAR(50),
    store_type VARCHAR(30),
    store_size_sqm INT,
    opening_date DATE,
    is_active TINYINT DEFAULT 1,
    PRIMARY KEY (dim_store_id),
    INDEX idx_store_code (store_code),
    INDEX idx_region (region, country)
) ENGINE=InnoDB;

CREATE TABLE dim_positions (
    dim_position_id INT NOT NULL AUTO_INCREMENT,
    position_code VARCHAR(20) NOT NULL,
    position_name VARCHAR(100) NOT NULL,
    department VARCHAR(50),
    division VARCHAR(50),
    PRIMARY KEY (dim_position_id),
    INDEX idx_position_code (position_code)
) ENGINE=InnoDB;

-- ============================================================================
-- FACT TABLE
-- ============================================================================

CREATE TABLE fact_planningcycle (
    fact_planningcycle_id BIGINT NOT NULL AUTO_INCREMENT,
    dim_position_id INT NOT NULL,
    planning_cycle_id INT NOT NULL,
    retailbrand_id INT NOT NULL,
    planning_cycle_year SMALLINT NOT NULL,
    assortment_season_id INT NOT NULL,
    assortment_season VARCHAR(20) NOT NULL,
    assortment_season_lifecycle VARCHAR(20) NOT NULL,
    week_in_season SMALLINT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    planned_sales_qty_tot DECIMAL(12,2) DEFAULT 0,
    forecast_sales_qty DECIMAL(12,2) DEFAULT 0,
    actual_sales_qty DECIMAL(12,2) DEFAULT 0,
    planned_revenue DECIMAL(14,2) DEFAULT 0,
    forecast_revenue DECIMAL(14,2) DEFAULT 0,
    dim_item_id INT NOT NULL,
    dim_store_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (fact_planningcycle_id),
    INDEX fk_fact_planningcycle_dim_positions1_idx (dim_position_id, planning_cycle_id, retailbrand_id),
    INDEX idx_fact_dim_item (dim_item_id),
    INDEX idx_fact_dim_store (dim_store_id),
    INDEX idx_fact_planning_cycle (planning_cycle_id, planning_cycle_year),
    INDEX idx_fact_season (assortment_season_id, week_in_season),
    INDEX idx_fact_dates (start_date, end_date),
    CONSTRAINT fk_fact_item FOREIGN KEY (dim_item_id) REFERENCES dim_items(dim_item_id),
    CONSTRAINT fk_fact_store FOREIGN KEY (dim_store_id) REFERENCES dim_stores(dim_store_id),
    CONSTRAINT fk_fact_position FOREIGN KEY (dim_position_id) REFERENCES dim_positions(dim_position_id)
) ENGINE=InnoDB;

-- ============================================================================
-- POPULATE DIMENSION DATA
-- ============================================================================

-- Insert 500 stores
DELIMITER //
CREATE PROCEDURE populate_dim_stores()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE regions VARCHAR(200) DEFAULT 'North,South,East,West,Central';
    DECLARE countries VARCHAR(200) DEFAULT 'UK,Germany,France,Spain,Italy,Netherlands,Sweden,Norway,Denmark,Finland';
    DECLARE store_types VARCHAR(100) DEFAULT 'Flagship,Standard,Outlet,Mini,Online';

    WHILE i <= 500 DO
        INSERT INTO dim_stores (store_code, store_name, region, country, city, store_type, store_size_sqm, opening_date)
        VALUES (
            CONCAT('STR-', LPAD(i, 5, '0')),
            CONCAT('Store ', i),
            ELT(1 + FLOOR(RAND() * 5), 'North','South','East','West','Central'),
            ELT(1 + FLOOR(RAND() * 10), 'UK','Germany','France','Spain','Italy','Netherlands','Sweden','Norway','Denmark','Finland'),
            CONCAT('City_', FLOOR(RAND() * 50)),
            ELT(1 + FLOOR(RAND() * 5), 'Flagship','Standard','Outlet','Mini','Online'),
            500 + FLOOR(RAND() * 4500),
            DATE_ADD('2010-01-01', INTERVAL FLOOR(RAND() * 5000) DAY)
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL populate_dim_stores();
DROP PROCEDURE populate_dim_stores;

-- Insert 5000 items
DELIMITER //
CREATE PROCEDURE populate_dim_items()
BEGIN
    DECLARE i INT DEFAULT 1;

    WHILE i <= 5000 DO
        INSERT INTO dim_items (item_code, item_name, category, subcategory, brand, color, size, unit_cost, unit_price)
        VALUES (
            CONCAT('ITM-', LPAD(i, 6, '0')),
            CONCAT('Item ', i),
            ELT(1 + FLOOR(RAND() * 8), 'Tops','Bottoms','Dresses','Outerwear','Footwear','Accessories','Sportswear','Underwear'),
            ELT(1 + FLOOR(RAND() * 6), 'Premium','Standard','Budget','Seasonal','Limited','Core'),
            ELT(1 + FLOOR(RAND() * 10), 'BrandA','BrandB','BrandC','BrandD','BrandE','BrandF','BrandG','BrandH','BrandI','BrandJ'),
            ELT(1 + FLOOR(RAND() * 8), 'Black','White','Blue','Red','Green','Grey','Navy','Brown'),
            ELT(1 + FLOOR(RAND() * 7), 'XS','S','M','L','XL','XXL','One Size'),
            ROUND(5 + RAND() * 95, 2),
            ROUND(15 + RAND() * 285, 2)
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL populate_dim_items();
DROP PROCEDURE populate_dim_items;

-- Insert 1000 positions
DELIMITER //
CREATE PROCEDURE populate_dim_positions()
BEGIN
    DECLARE i INT DEFAULT 1;

    WHILE i <= 1000 DO
        INSERT INTO dim_positions (position_code, position_name, department, division)
        VALUES (
            CONCAT('POS-', LPAD(i, 5, '0')),
            CONCAT('Position ', i),
            ELT(1 + FLOOR(RAND() * 6), 'Menswear','Womenswear','Kidswear','Sportswear','Accessories','Home'),
            ELT(1 + FLOOR(RAND() * 4), 'Retail','Wholesale','Ecommerce','Outlet')
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL populate_dim_positions();
DROP PROCEDURE populate_dim_positions;

-- ============================================================================
-- POPULATE FACT TABLE (1.2M rows in batches)
-- ============================================================================

DELIMITER //
CREATE PROCEDURE populate_fact_planningcycle()
BEGIN
    DECLARE batch INT DEFAULT 0;
    DECLARE batch_size INT DEFAULT 10000;
    DECLARE total_batches INT DEFAULT 120;
    DECLARE i INT;
    DECLARE v_position_id INT;
    DECLARE v_item_id INT;
    DECLARE v_store_id INT;
    DECLARE v_cycle_id INT;
    DECLARE v_brand_id INT;
    DECLARE v_year SMALLINT;
    DECLARE v_season_id INT;
    DECLARE v_season VARCHAR(20);
    DECLARE v_lifecycle VARCHAR(20);
    DECLARE v_week SMALLINT;
    DECLARE v_start DATE;

    WHILE batch < total_batches DO
        SET i = 0;
        START TRANSACTION;

        WHILE i < batch_size DO
            SET v_position_id = 1 + FLOOR(RAND() * 1000);
            SET v_item_id = 1 + FLOOR(RAND() * 5000);
            SET v_store_id = 1 + FLOOR(RAND() * 500);
            SET v_cycle_id = 1 + FLOOR(RAND() * 20);
            SET v_brand_id = 1 + FLOOR(RAND() * 15);
            SET v_year = 2022 + FLOOR(RAND() * 4);
            SET v_season_id = 1 + FLOOR(RAND() * 8);
            SET v_season = ELT(1 + FLOOR(RAND() * 4), 'Spring','Summer','Autumn','Winter');
            SET v_lifecycle = ELT(1 + FLOOR(RAND() * 4), 'Launch','Growth','Maturity','Decline');
            SET v_week = 1 + FLOOR(RAND() * 52);
            SET v_start = DATE_ADD('2022-01-01', INTERVAL FLOOR(RAND() * 1460) DAY);

            INSERT INTO fact_planningcycle (
                dim_position_id, planning_cycle_id, retailbrand_id,
                planning_cycle_year, assortment_season_id, assortment_season,
                assortment_season_lifecycle, week_in_season, start_date, end_date,
                planned_sales_qty_tot, forecast_sales_qty, actual_sales_qty,
                planned_revenue, forecast_revenue, dim_item_id, dim_store_id
            ) VALUES (
                v_position_id, v_cycle_id, v_brand_id,
                v_year, v_season_id, v_season,
                v_lifecycle, v_week, v_start, DATE_ADD(v_start, INTERVAL 7 DAY),
                ROUND(RAND() * 500, 2), ROUND(RAND() * 450, 2), ROUND(RAND() * 400, 2),
                ROUND(RAND() * 50000, 2), ROUND(RAND() * 45000, 2),
                v_item_id, v_store_id
            );

            SET i = i + 1;
        END WHILE;

        COMMIT;
        SET batch = batch + 1;

        IF batch MOD 10 = 0 THEN
            SELECT CONCAT('Loaded ', batch * batch_size, ' rows...') AS progress;
        END IF;
    END WHILE;
END //
DELIMITER ;

SELECT 'Starting fact table population (1.2M rows)...' AS status;
CALL populate_fact_planningcycle();
DROP PROCEDURE populate_fact_planningcycle;

-- ============================================================================
-- VERIFY DATA
-- ============================================================================

SELECT 'Data population complete. Row counts:' AS status;
SELECT 'dim_stores' AS tbl, COUNT(*) AS row_count FROM dim_stores
UNION ALL
SELECT 'dim_items', COUNT(*) FROM dim_items
UNION ALL
SELECT 'dim_positions', COUNT(*) FROM dim_positions
UNION ALL
SELECT 'fact_planningcycle', COUNT(*) FROM fact_planningcycle;

-- Update index statistics
ANALYZE TABLE fact_planningcycle;
ANALYZE TABLE dim_items;
ANALYZE TABLE dim_stores;
ANALYZE TABLE dim_positions;

SELECT 'Setup complete. Ready for parallel testing.' AS status;
