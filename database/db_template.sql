-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: mysql
-- Tiempo de generación: 30-08-2025 a las 12:46:27
-- Versión del servidor: 9.1.0
-- Versión de PHP: 8.2.8

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "-05:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `db_template`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`%` PROCEDURE `DeactivateInactivePageEndpoints` ()   BEGIN
    DECLARE inactivity_limit_days INT DEFAULT 7; -- Limit in days for inactivity

    -- Update relationships that are inactive and not already deactivated
    UPDATE config_pages_has_endpoints
    SET deleted_at = NOW()
    WHERE deleted_at IS NULL
      AND ShouldDeactivatePageEndpoint(updated_at, inactivity_limit_days);
END$$

CREATE DEFINER=`root`@`%` PROCEDURE `ReceiveWarehouseAssetTransfer` (IN `in_id_movement` INT, IN `in_id_warehouse` INT, IN `in_id_contract` INT, IN `in_today` DATE)  DETERMINISTIC MODIFIES SQL DATA SQL SECURITY INVOKER COMMENT 'Receives satisfaction with the transfer from one warehouse to an' BEGIN
    -- Receives the warehouse asset transfer to satisfaction
    DECLARE v_id_asset INT;
    DECLARE v_quantity INT;
    DECLARE v_id_inventory INT;
    DECLARE v_id_detail INT;

    -- Step 1: Query the transfer movement
    SELECT id_asset, quantity 
    INTO v_id_asset, v_quantity
    FROM inv_movements
    WHERE id = in_id_movement
    AND status = 'process'
    AND deleted_at IS NULL;

    -- If the movement is not found, raise an exception
    IF v_id_asset IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer movement not found or already completed.';
    END IF;

    -- Step 2: Insert a new movement record for the receiving warehouse
    INSERT INTO inv_movements (id_type, id_asset, id_warehouse, id_contract, id_movement, quantity, status)
    VALUES (2, v_id_asset, in_id_warehouse, in_id_contract, in_id_movement, v_quantity, 'process');

    -- Step 3: Check if there's an active inventory in the receiving warehouse
    SELECT id 
    INTO v_id_inventory
    FROM inv_inventories
    WHERE id_warehouse = in_id_warehouse
    AND start_date <= in_today
    AND end_date >= in_today
    AND deleted_at IS NULL;

    -- If no active inventory is found, raise an exception
    IF v_id_inventory IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No active inventory found for the warehouse.';
    END IF;

    -- Step 4: Check if there's an inventory detail for the asset in the active inventory
    SELECT id 
    INTO v_id_detail
    FROM inv_inventories_details
    WHERE id_inventory = v_id_inventory
    AND id_asset = v_id_asset;

    -- If no inventory detail exists, create a new one
    IF ROW_COUNT() = 0 THEN
        INSERT INTO inv_inventories_details (id_inventory, id_asset, stock)
        VALUES (v_id_inventory, v_id_asset, v_quantity);
    END IF;

    -- Step 5: Update the stock in the inventory detail
    UPDATE inv_inventories_details
    SET stock = stock + v_quantity, deleted_at = NULL
    WHERE id = v_id_detail;

    -- Step 6: Mark the first movement as 'done'
    UPDATE inv_movements
    SET status = 'done'
    WHERE id = in_id_movement;

    -- Step 7: Mark the second movement as 'done'
    UPDATE inv_movements
    SET status = 'done'
    WHERE id = LAST_INSERT_ID();

END$$

CREATE DEFINER=`root`@`%` PROCEDURE `RecordWarehouseAssetTransfer` (IN `in_id_asset` INT, IN `in_id_warehouse` INT, IN `in_id_contract` INT, IN `in_quantity` INT, IN `in_today` DATE, OUT `out_id_movement` INT)  MODIFIES SQL DATA SQL SECURITY INVOKER COMMENT 'Records a transfer of assets from one warehouse to another.' BEGIN
    DECLARE id_movement INT;
    DECLARE id_inventory INT;
    DECLARE id_detail INT;

    -- Step 1: Insert the movement record
    INSERT INTO inv_movements (id_type, id_asset, id_warehouse, id_contract, quantity)
    VALUES (1, in_id_asset, in_id_warehouse, in_id_contract, in_quantity);

    -- Step 2: Retrieve the ID of the newly created movement
    SET id_movement = LAST_INSERT_ID();

    -- Step 3: Check if there is an active inventory in the specified warehouse
    SELECT id INTO id_inventory
    FROM inv_inventories
    WHERE id_warehouse = in_id_warehouse
      AND start_date <= in_today
      AND end_date >= in_today
      AND deleted_at IS NULL
    LIMIT 1;

    -- If no active inventory is found, raise an exception
    IF id_inventory IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No active inventory found in the specified warehouse';
    END IF;

    -- Step 4: Check if the active inventory has enough stock for the asset
    SELECT id INTO id_detail
    FROM inv_inventories_details
    WHERE id_inventory = id_inventory
      AND id_asset = in_id_asset
      AND stock >= in_quantity
    LIMIT 1;

    -- If no sufficient stock is found, raise an exception
    IF id_detail IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Not enough stock in the active inventory for the specified asset';
    END IF;

    -- Step 5: Reduce the stock in the inventory detail
    UPDATE inv_inventories_details
    SET stock = stock - in_quantity,
        deleted_at = NULL
    WHERE id = id_detail;

    -- Step 6: Update the movement status to 'process'
    UPDATE inv_movements
    SET status = 'process'
    WHERE id = id_movement;

    -- Set the OUT parameter with the ID of the newly created movement
    SET out_id_movement = id_movement;
END$$

--
-- Funciones
--
CREATE DEFINER=`root`@`%` FUNCTION `ShouldDeactivatePageEndpoint` (`last_updated` TIMESTAMP, `limit_days` INT) RETURNS TINYINT(1) DETERMINISTIC BEGIN
    -- Determine if a page-endpoint relationship should be deactivated based on inactivity
    RETURN DATEDIFF(NOW(), last_updated) > limit_days;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `ai_assistants`
--

CREATE TABLE `ai_assistants` (
  `id` int NOT NULL COMMENT 'Autonumerical identifier for each AI assistant.',
  `name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the AI assistant.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Descriptive summary of the functions and objectives of the AI assistant.',
  `base_propmpt` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Prompt base for the AI assistant.',
  `keywords` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Keywords for the AI assistant''s functions, objectives, and more.',
  `api_key` blob NOT NULL COMMENT 'Assistant API Key.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='AI assistants available for the app.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cli_branches`
--

CREATE TABLE `cli_branches` (
  `id` int NOT NULL COMMENT 'Unique identifier for each company branch.',
  `company_id` int NOT NULL COMMENT 'ID of the company to which the branch belongs.',
  `country_id` int NOT NULL COMMENT 'ID of the country where the branch is located. NULL for virtual branches.',
  `city_id` int DEFAULT NULL COMMENT 'ID of the city where the branch is located. NULL for virtual branches.',
  `internal_code` varchar(20) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Internal identification code of the headquarters.',
  `branch_code` varchar(20) COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Internal code to identify the branch.',
  `name` varchar(200) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the branch or office.',
  `type` enum('physical','virtual','hybrid') COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'physical' COMMENT 'Type of branch: physical office, virtual office, or hybrid.',
  `is_headquarters` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates if this is the main headquarters.',
  `address` text COLLATE utf8mb4_general_ci COMMENT 'Physical address of the branch. NULL for virtual branches.',
  `postal_code` varchar(20) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Postal code of the branch.',
  `status` enum('active','inactive','under_construction','closed') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Current status of the branch.',
  `notes` text COLLATE utf8mb4_general_ci COMMENT 'Additional notes about the branch.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Company branches and offices, including virtual offices.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cli_companies`
--

CREATE TABLE `cli_companies` (
  `id` int NOT NULL COMMENT 'Unique identifier for each client company.',
  `country_id` int NOT NULL COMMENT 'ID of the country where the company is legally registered.',
  `city_id` int DEFAULT NULL COMMENT 'ID of the city where the main headquarters is located.',
  `legal_document` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Legal identification document number of the company.',
  `id_tax` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Tax identification number for fiscal purposes.',
  `legal_name` varchar(200) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Official legal name of the company as registered.',
  `commercial_name` varchar(200) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Commercial or trade name used by the company.',
  `logo` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'URL or path to the company logo image.',
  `industry` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Industry sector or business category of the company.',
  `company_size` enum('startup','small','medium','large','enterprise') COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'small' COMMENT '''Size classification of the company based on employees or revenue.''',
  `is_multinational` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates if the company operates in multiple countries.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Stores information about client companies.';

--
-- Volcado de datos para la tabla `cli_companies`
--

INSERT INTO `cli_companies` (`id`, `country_id`, `city_id`, `legal_document`, `id_tax`, `legal_name`, `commercial_name`, `logo`, `industry`, `company_size`, `is_multinational`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 48, NULL, '1070627714', '1', 'Owner Company S.A.S.', 'Owner Company', NULL, 'Software', 'startup', 0, '2025-07-13 17:06:32', '2025-07-13 17:06:32', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cli_contacts`
--

CREATE TABLE `cli_contacts` (
  `id` int NOT NULL COMMENT 'Unique identifier for each contact.',
  `branch_id` int NOT NULL COMMENT 'ID of the branch to which the contact information belongs.',
  `department_id` int DEFAULT NULL COMMENT 'Department ID to which the contact information belongs.',
  `main_email` varchar(150) COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Primary contact email.',
  `secondary_email` varchar(150) COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Secondary contact email.',
  `main_landline` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Main contact landline phone number.',
  `secondary_landline` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Secondary landline phone number.',
  `main_mobile_number_options` json DEFAULT NULL COMMENT 'Options associated with the primary contact mobile phone number.',
  `secondary_mobile_number_options` json DEFAULT NULL COMMENT 'Options associated with the alternate contact mobile phone number.',
  `description` tinytext COLLATE utf8mb4_general_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Contact information for companies, offices and/or department';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cli_departments`
--

CREATE TABLE `cli_departments` (
  `id` int NOT NULL COMMENT 'Unique identifier for each department.',
  `company_id` int NOT NULL COMMENT 'ID of the company to which the department belongs.',
  `branch_id` int DEFAULT NULL COMMENT 'ID of the branch where the department is located. NULL for company-wide departments.',
  `parent_department_id` int DEFAULT NULL COMMENT 'ID of the parent department for hierarchical structure.',
  `internal_code` varchar(20) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Internal code to identify the department.',
  `name` varchar(200) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the department.',
  `description` text COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Description of the department responsibilities.',
  `type` enum('operational','administrative','support','strategic') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Type of department classification.',
  `level` tinyint NOT NULL COMMENT 'Indicates if the department operates virtually.',
  `is_virtual` tinyint(1) NOT NULL COMMENT 'Indicates if the department operates virtually.',
  `objectives` text COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Department objectives and goals.',
  `status` enum('active','inactive','restructuring','dissolved') COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'active' COMMENT 'Current status of the department.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Departments and areas within companies.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cli_social_networks`
--

CREATE TABLE `cli_social_networks` (
  `id` int NOT NULL COMMENT 'Unique identifier for each of the company''s social networks.',
  `company_id` int NOT NULL COMMENT 'ID of the company to which the social network belongs.',
  `type_network` enum('facebook','whatsapp','instagram','twitter','linkedin','website','other') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Type of social network.',
  `url` tinytext COLLATE utf8mb4_general_ci NOT NULL COMMENT 'URL to access the social network.',
  `nickname` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Username, @ or nickname of the account.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Social networks of client companies.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_endpoints`
--

CREATE TABLE `config_endpoints` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each endpoint.',
  `method` enum('post','get','put','patch','delete','options') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Method of the endpoint to which permission will be granted.',
  `platform` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Target platform for the endpoint configuration',
  `version` varchar(10) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Version identifier of the endpoint configuration',
  `endpoint_group` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Grouping of different endpoints',
  `path` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Path of the endpoint to which permission will be granted.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Optional description of the endpoint''s function.',
  `requires_authorization` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether or not the endpoint requires authorization to be executed.',
  `has_sensitive_information` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the page contains sensitive information. Useful for defining what is and is not allowed in "safe mode."',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table with the permissions of a role with the endpoints.';

--
-- Volcado de datos para la tabla `config_endpoints`
--

INSERT INTO `config_endpoints` (`id`, `method`, `platform`, `version`, `endpoint_group`, `path`, `description`, `requires_authorization`, `has_sensitive_information`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 'post', 'web', 'v1', 'auth', '/signup', NULL, 1, 1, '2025-07-15 01:11:42', '2025-07-19 20:14:20', '2025-07-19 20:14:20'),
(2, 'post', 'web', 'v1', 'auth', '/resend-confirmation-email', NULL, 1, 1, '2025-07-15 01:11:42', '2025-07-19 20:14:20', '2025-07-19 20:14:20');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_endpoints_has_required_scopes`
--

CREATE TABLE `config_endpoints_has_required_scopes` (
  `id` int NOT NULL COMMENT 'Unique identifier for each relationship between endpoint and mandatory scope.',
  `endpoint_id` int NOT NULL COMMENT 'Endpoint ID.',
  `scope_id` int NOT NULL COMMENT 'Scope ID that the user must have in order to run the endpoint.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship between scopes and endpoints.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_endpoints_request_schema`
--

CREATE TABLE `config_endpoints_request_schema` (
  `id` int NOT NULL COMMENT 'Primary key. Unique auto-incrementing identifier for each request schema parameter record',
  `endpoint_id` int NOT NULL COMMENT 'Foreign key reference to the associated API endpoint. Identifies which endpoint this parameter belongs to',
  `field_id` int DEFAULT NULL COMMENT 'ID of the field to which it belongs. This is used for cases where the field is an object or an array of objects.',
  `name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Canonical name of the request parameter as expected by the API (e.g. in URL, headers, or body). Case-sensitive',
  `alias` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Optional alternative name for the parameter (e.g. deprecated names or client-facing names). Shown in documentation instead of name when present',
  `location` enum('body','params','query','header','auth_token') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Field location in the request: body, parameters (path), query (URL), header, or auth_token',
  `data_type` enum('string','integer','boolean','array','object','file','float') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Expected data type for the parameter. Defines how the input should be parsed and validated',
  `is_required` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates if the parameter is mandatory (TRUE) or optional (FALSE) for the request',
  `required_condition` json DEFAULT NULL COMMENT 'JSON structure defining conditional requirements (e.g. required only when other fields exist). Example: {"if_field": "payment_type", "is": "credit_card"}',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Defines request parameters for API endpoints.';

--
-- Volcado de datos para la tabla `config_endpoints_request_schema`
--

INSERT INTO `config_endpoints_request_schema` (`id`, `endpoint_id`, `field_id`, `name`, `alias`, `location`, `data_type`, `is_required`, `required_condition`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, NULL, 'firstName', NULL, 'body', 'string', 1, NULL, '2025-07-15 01:11:42', '2025-07-15 01:16:41', '2025-07-15 01:13:53'),
(2, 1, NULL, 'firstLastName', NULL, 'body', 'string', 1, NULL, '2025-07-15 01:11:42', '2025-07-15 01:16:41', '2025-07-15 01:13:53'),
(3, 1, NULL, 'email', NULL, 'body', 'string', 1, NULL, '2025-07-15 01:11:42', '2025-07-15 01:16:41', '2025-07-15 01:13:53'),
(4, 1, NULL, 'password', NULL, 'body', 'string', 1, NULL, '2025-07-15 01:11:42', '2025-07-15 01:16:41', '2025-07-15 01:13:53'),
(5, 2, NULL, 'email', NULL, 'body', 'string', 1, NULL, '2025-07-15 01:11:42', '2025-07-15 01:16:41', '2025-07-15 01:13:53'),
(10, 1, NULL, 'preferences', NULL, 'body', 'object', 0, NULL, '2025-07-19 20:15:31', '2025-07-19 20:15:31', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_hosts`
--

CREATE TABLE `config_hosts` (
  `id` int NOT NULL COMMENT 'Unique identifier for each host.',
  `company_id` int NOT NULL COMMENT 'ID of the company to which the host belongs.',
  `url` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'URN of the allowed hosts.',
  `version` tinyint NOT NULL COMMENT 'Indicates which version of the API this is expected to work for.',
  `is_default` tinyint(1) NOT NULL COMMENT 'Indicates whether this is the default host or not. There can only be one.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Supported hosts that can use the API.';

--
-- Volcado de datos para la tabla `config_hosts`
--

INSERT INTO `config_hosts` (`id`, `company_id`, `url`, `version`, `is_default`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, 'http://localhost:5173', 1, 1, '2025-04-23 01:01:02', '2025-07-13 19:10:02', NULL),
(2, 1, 'http://localhost:8080', 1, 0, '2025-04-23 01:01:44', '2025-07-13 19:10:05', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_pages`
--

CREATE TABLE `config_pages` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each page.',
  `host_id` int NOT NULL COMMENT 'ID of the client to which the page belongs.',
  `page_id` int DEFAULT NULL COMMENT 'ID of the parent page to which the child belongs. If null, it is a "first-line page".',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Page name (extracted from Vue router 4).',
  `path` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Path of the specific page for identification. It must be exactly the same as the path used by the end user to access the view.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Optional description of what can be done or viewed on the page.',
  `level` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether it is level 1, 2, or 3 (this being the last level allowed).',
  `requires_authorization` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether the page requires authorization to access it.',
  `has_sensitive_information` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the page contains sensitive information. Useful for defining what is and is not allowed in "safe mode."',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the application''s frontend pages.';

--
-- Volcado de datos para la tabla `config_pages`
--

INSERT INTO `config_pages` (`id`, `host_id`, `page_id`, `name`, `path`, `description`, `level`, `requires_authorization`, `has_sensitive_information`, `created_at`, `updated_at`, `deleted_at`) VALUES
(3, 1, NULL, 'signup', '/signup', 'Registro de usuario', 1, 1, 1, '2025-07-14 18:24:27', '2025-07-14 18:24:27', NULL),
(4, 1, NULL, 'confirm-account', '/confirm-account', NULL, 1, 0, 0, '2025-07-14 18:56:38', '2025-07-14 18:56:38', NULL),
(5, 2, NULL, 'confirm-account', '/confirm-account', NULL, 1, 0, 0, '2025-07-14 18:56:38', '2025-07-14 18:56:38', NULL),
(6, 1, NULL, 'resend-confirmation-email', '/resend-confirmation-email', 'Reenviar correo de confirmaciÃ³n de cuenta', 1, 0, 0, '2025-07-14 23:52:08', '2025-07-19 16:35:18', NULL),
(7, 1, NULL, 'confirm-account-email', '/confirm-account-email', 'Reenviar correo de confirmaciÃ³n de cuenta', 1, 0, 0, '2025-07-19 16:19:12', '2025-07-19 16:19:12', NULL),
(8, 1, NULL, 'index', '/', NULL, 1, 0, 0, '2025-07-19 16:35:07', '2025-07-19 16:35:07', NULL),
(9, 1, NULL, 'login', '/login', 'Iniciar sesiÃ³n', 1, 0, 0, '2025-07-19 18:44:01', '2025-07-19 18:44:01', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_pages_endpoints_has_schemas`
--

CREATE TABLE `config_pages_endpoints_has_schemas` (
  `id` int NOT NULL COMMENT 'Primary key, unique identifier for each page-endpoint-field relationship.',
  `id_page_endpoint` int NOT NULL COMMENT 'Foreign key referencing the page-endpoint relationship.',
  `id_endpoint_field` int NOT NULL COMMENT 'Foreign key referencing the specific endpoint field configuration.',
  `location` enum('body','params','query','header','auth_token') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Field location in the request from the page: body, parameters (path), query (URL), header, or auth_token',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Maps which fields are used in page-endpoint relationships';

--
-- Volcado de datos para la tabla `config_pages_endpoints_has_schemas`
--

INSERT INTO `config_pages_endpoints_has_schemas` (`id`, `id_page_endpoint`, `id_endpoint_field`, `location`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, 5, 'body', '2025-07-15 01:14:29', '2025-07-15 01:14:29', NULL),
(2, 2, 1, 'body', '2025-07-15 01:20:55', '2025-07-15 01:20:55', NULL),
(3, 2, 2, 'body', '2025-07-15 01:20:55', '2025-07-15 01:20:55', NULL),
(4, 2, 3, 'body', '2025-07-15 01:20:55', '2025-07-15 01:20:55', NULL),
(5, 2, 4, 'body', '2025-07-15 01:20:55', '2025-07-15 01:20:55', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_pages_has_endpoints`
--

CREATE TABLE `config_pages_has_endpoints` (
  `id` int NOT NULL COMMENT 'Unique identifier for each page-endpoint relationship.',
  `id_page` int NOT NULL COMMENT 'Page ID.',
  `id_endpoint` int NOT NULL COMMENT 'Endpoint ID.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship of endpoint usage on each page.';

--
-- Volcado de datos para la tabla `config_pages_has_endpoints`
--

INSERT INTO `config_pages_has_endpoints` (`id`, `id_page`, `id_endpoint`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 6, 2, '2025-07-15 01:14:29', '2025-08-03 16:56:36', '2025-08-03 16:56:36'),
(2, 3, 1, '2025-07-15 01:20:55', '2025-08-03 16:56:36', '2025-08-03 16:56:36');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_pages_has_required_scopes`
--

CREATE TABLE `config_pages_has_required_scopes` (
  `id` int NOT NULL COMMENT 'Unique identifier for each relationship between page and mandatory scope.',
  `page_id` int NOT NULL COMMENT 'Page ID.',
  `scope_id` int NOT NULL COMMENT 'Scope ID that the user must have in order to run the page.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship between scopes and pages.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_roles`
--

CREATE TABLE `config_roles` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each rol.',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Role name.',
  `target` enum('everyone','employee','client','provider','client_user','project') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'everyone' COMMENT 'Defines who the profiles are available for (linked to the tables that store user information).',
  `is_default` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the role is the default. There can only be one per target.',
  `security_level` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Role security level to relate it to the permissions of each endpoint.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores roles and their availability.';

--
-- Volcado de datos para la tabla `config_roles`
--

INSERT INTO `config_roles` (`id`, `name`, `target`, `is_default`, `security_level`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 'administration', 'everyone', 1, 2, '2024-09-01 20:06:43', '2025-06-25 15:04:59', NULL),
(2, 'support', 'employee', 0, 1, '2024-09-01 20:06:43', '2024-09-01 20:06:43', NULL),
(3, 'Visitor', 'everyone', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(4, 'Guest', 'everyone', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(5, 'Administrator', 'employee', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(6, 'Manager', 'employee', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(7, 'Staff', 'employee', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(8, 'Intern', 'employee', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(9, 'Premium Client', 'client', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(10, 'Regular Client', 'client', 1, 1, '2025-01-23 15:01:11', '2025-06-25 15:47:59', NULL),
(11, 'New Client', 'client', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(12, 'Supplier', 'provider', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(13, 'Vendor', 'provider', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(14, 'Contractor', 'provider', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(15, 'Client User', 'client_user', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(16, 'Client Admin', 'client_user', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(17, 'Project Manager', 'project', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(18, 'Project Contributor', 'project', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL),
(19, 'Project Viewer', 'project', 0, 1, '2025-01-23 15:01:11', '2025-01-23 15:01:11', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_roles_has_scopes`
--

CREATE TABLE `config_roles_has_scopes` (
  `id` int NOT NULL COMMENT 'Unique identifier for the relationship between role and scope.',
  `role_id` int NOT NULL COMMENT 'Role ID.',
  `scope_id` int NOT NULL COMMENT 'Scope ID.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Scopes that each role has.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_scopes`
--

CREATE TABLE `config_scopes` (
  `id` int NOT NULL COMMENT 'Unique identifier for each scope.',
  `name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique scope name (in snake_case and separated by a colon).',
  `description` text COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Description of the permissions that the scope has.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='System-wide scopes.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_shorteners`
--

CREATE TABLE `config_shorteners` (
  `id` int NOT NULL COMMENT 'Autonumeric identifier for each link shortener.',
  `url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Full URL.',
  `code_shortener` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique identification code for link.',
  `expires_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time limit for use of the shortener.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Codes assigned to different links to cut them.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `config_taxes`
--

CREATE TABLE `config_taxes` (
  `id` int NOT NULL COMMENT 'Unique identifier for each tax configuration.',
  `id_country` int NOT NULL COMMENT 'ID of the country where the tax is applied.',
  `id_sub_division` int DEFAULT NULL COMMENT 'ID of the subdivision (state, province, or department) where the tax is applied. Nullable for nationwide taxes.',
  `id_city` int DEFAULT NULL COMMENT 'ID of the city where the tax is applied. Nullable for taxes applied at higher administrative levels.',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the tax (e.g., VAT, Sales Tax).',
  `rate` decimal(5,2) NOT NULL COMMENT 'Tax rate as a percentage (e.g., 18.00 for 18%).',
  `applicable_to` enum('product','service','both','income','operations') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Indicates what the tax applies to: products, services, both, income, or general operations.',
  `type` enum('collected','payable') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Defines whether the tax is collected (from customers) or payable (to government).',
  `effective_date` date NOT NULL COMMENT 'Date when the tax becomes effective.',
  `end_date` date DEFAULT NULL COMMENT 'Date when the tax ends. NULL means it is currently active.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table to store tax configurations.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `data_currencies`
--

CREATE TABLE `data_currencies` (
  `id` int NOT NULL COMMENT 'Unique identifier for each currency.',
  `name` json NOT NULL COMMENT 'Official name of the currency in several languages.',
  `abbreviation` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Abbreviation for currency.',
  `symbol` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Symbol that differentiates the currency.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Currencies of each country.';

--
-- Volcado de datos para la tabla `data_currencies`
--

INSERT INTO `data_currencies` (`id`, `name`, `abbreviation`, `symbol`) VALUES
(1, '{\"en\": \"Afghan afghani\", \"es\": \"Afgani afgano\"}', 'AFN', '؋'),
(2, '{\"en\": \"United Arab Emirates Dirham\", \"es\": \"Dirham de los Emiratos Árabes Unidos\"}', 'AED', 'د.إ'),
(3, '{\"en\": \"Albanian lek\", \"es\": \"Lek albanés\"}', 'ALL', 'Lek'),
(4, '{\"en\": \"Armenian dram\", \"es\": \"Dram armenio\"}', 'AMD', '֏'),
(5, '{\"en\": \"Netherlands Antillean guilder\", \"es\": \"Guilder de las Antillas Neerlandesas\"}', 'ANG', 'ƒ'),
(6, '{\"en\": \"Angolan kwanza\", \"es\": \"Kwanza angoleño\"}', 'AOA', 'Kz'),
(7, '{\"en\": \"Argentine peso\", \"es\": \"Peso argentino\"}', 'ARS', '$'),
(8, '{\"en\": \"Australian dollar\", \"es\": \"Dólar australiano\"}', 'AUD', '$'),
(9, '{\"en\": \"Aruban florin\", \"es\": \"Florín arubeño\"}', 'AWG', 'ƒ'),
(10, '{\"en\": \"Azerbaijani manat\", \"es\": \"Manat azerbaiyano\"}', 'AZN', '₼'),
(11, '{\"en\": \"Bosnia and Herzegovina Convertible Mark\", \"es\": \"Marco convertible de Bosnia y Herzegovina\"}', 'BAM', 'KM'),
(12, '{\"en\": \"Barbadian Dollar\", \"es\": \"Dólar Barbadense\"}', 'BBD', '$'),
(13, '{\"en\": \"Bangladeshi Taka\", \"es\": \"Taka de Bangladesh\"}', 'BDT', '৳'),
(14, '{\"en\": \"Bulgarian Lev\", \"es\": \"Lev búlgaro\"}', 'BGN', 'лв'),
(15, '{\"en\": \"Bahraini dinar\", \"es\": \"Dinar bareiní\"}', 'BHD', '.د.ب'),
(16, '{\"en\": \"Burundian Franc\", \"es\": \"Franco burundiano\"}', 'BIF', 'Fr'),
(17, '{\"en\": \"Bermudian Dollar\", \"es\": \"Dólar bermudeño\"}', 'BMD', '$'),
(18, '{\"en\": \"Brunei Dollar\", \"es\": \"Dólar de Brunei\"}', 'BND', '$'),
(19, '{\"en\": \"Bolivian Boliviano\", \"es\": \"Boliviano boliviano\"}', 'BOB', 'Bs.'),
(20, '{\"en\": \"Brazilian Real\", \"es\": \"Real brasileño\"}', 'BRL', 'R$'),
(21, '{\"en\": \"Bahamian dollar\", \"es\": \"Dólar bahameño\"}', 'BSD', '$'),
(22, '{\"en\": \"Bhutanese Ngultrum\", \"es\": \"Ngultrum de Bután\"}', 'BTN', 'Nu.'),
(23, '{\"en\": \"Botswana Pula\", \"es\": \"Pula de Botsuana\"}', 'BWP', 'P'),
(24, '{\"en\": \"Belarusian Ruble\", \"es\": \"Rublo bielorruso\"}', 'BYN', 'Br'),
(25, '{\"en\": \"Belize Dollar\", \"es\": \"Dólar de Belice\"}', 'BZD', '$'),
(26, '{\"en\": \"Canadian Dollar\", \"es\": \"Dólar canadiense\"}', 'CAD', '$'),
(27, '{\"en\": \"Congolese Franc\", \"es\": \"Franco Congoleño\"}', 'CDF', 'FC'),
(28, '{\"en\": \"Swiss Franc\", \"es\": \"Franco suizo\"}', 'CHF', 'Fr.'),
(29, '{\"en\": \"Chilean Peso\", \"es\": \"Peso chileno\"}', 'CLP', '$'),
(30, '{\"en\": \"Renminbi\", \"es\": \"Renminbi\"}', 'CNY', '¥'),
(31, '{\"en\": \"Colombian Peso\", \"es\": \"Peso colombiano\"}', 'COP', '$'),
(32, '{\"en\": \"Costa Rican Colón\", \"es\": \"Colón costarricense\"}', 'CRC', '₡'),
(33, '{\"en\": \"Convertible Peso\", \"es\": \"Peso Convertible\"}', 'CUC', '₱'),
(34, '{\"en\": \"Cuban Peso\", \"es\": \"Peso Cubano\"}', 'CUP', '₱'),
(35, '{\"en\": \"Cape Verdean Escudo\", \"es\": \"Escudo caboverdiano\"}', 'CVE', 'Esc'),
(36, '{\"en\": \"Czech Koruna\", \"es\": \"Corona Checa\"}', 'CZK', 'Kč'),
(37, '{\"en\": \"Djiboutian Franc\", \"es\": \"Franco Djibutiano\"}', 'DJF', 'Fdj'),
(38, '{\"en\": \"Danish Krone\", \"es\": \"Corona danesa\"}', 'DKK', 'kr'),
(39, '{\"en\": \"Dominican Peso\", \"es\": \"Peso Dominicano\"}', 'DOP', 'RD$'),
(40, '{\"en\": \"Algerian dinar\", \"es\": \"Dinar argelino\"}', 'DZD', 'دج'),
(41, '{\"en\": \"Egyptian Pound\", \"es\": \"Libra Egipcia\"}', 'EGP', '£'),
(42, '{\"en\": \"Eritrean Nakfa\", \"es\": \"Nakfa Eritreo\"}', 'ERN', 'Nfk'),
(43, '{\"en\": \"Ethiopian Birr\", \"es\": \"Birr etíope\"}', 'ETB', 'ብር'),
(44, '{\"en\": \"Euro\", \"es\": \"Euro\"}', 'EUR', '€'),
(45, '{\"en\": \"Fijian Dollar\", \"es\": \"Dólar fiyiano\"}', 'FJD', '$'),
(46, '{\"en\": \"Falkland Islands Pound\", \"es\": \"Libra de las Islas Malvinas\"}', 'FKP', '£'),
(47, '{\"en\": \"Pound Sterling\", \"es\": \"Libra esterlina\"}', 'GBP', '£'),
(48, '{\"en\": \"Georgian Lari\", \"es\": \"Lari georgiano\"}', 'GEL', '₾'),
(49, '{\"en\": \"Guernsey pound\", \"es\": \"Libra de Guernsey\"}', 'GGP', '£'),
(50, '{\"en\": \"Ghanaian Cedi\", \"es\": \"Cedi ghanés\"}', 'GHS', '₵'),
(51, '{\"en\": \"Gibraltar Pound\", \"es\": \"Libra de Gibraltar\"}', 'GIP', '£'),
(52, '{\"en\": \"Gambian Dalasi\", \"es\": \"Dalasi gambiano\"}', 'GMD', 'D'),
(53, '{\"en\": \"Guinean franc\", \"es\": \"Franco guineano\"}', 'GNF', 'FG'),
(54, '{\"en\": \"Guatemalan quetzal\", \"es\": \"Quetzal guatemalteco\"}', 'GTQ', 'Q'),
(55, '{\"en\": \"Guyanese dollar\", \"es\": \"Dólar guyanés\"}', 'GYD', '$'),
(56, '{\"en\": \"Hong Kong dollar\", \"es\": \"Dólar de Hong Kong\"}', 'HKD', '$'),
(57, '{\"en\": \"Honduran lempira\", \"es\": \"Lempira hondureño\"}', 'HNL', 'L'),
(58, '{\"en\": \"Croatian Kuna\", \"es\": \"Kuna croata\"}', 'HRK', 'kn'),
(59, '{\"en\": \"Haitian gourde\", \"es\": \"Gourde haitiano\"}', 'HTG', 'G'),
(60, '{\"en\": \"Hungarian forint\", \"es\": \"Forinto húngaro\"}', 'HUF', 'Ft'),
(61, '{\"en\": \"Indonesian rupiah\", \"es\": \"Rupia indonesia\"}', 'IDR', 'Rp'),
(62, '{\"en\": \"Israeli New Shekel\", \"es\": \"Shekel israelí\"}', 'ILS', '₪'),
(63, '{\"en\": \"Indian rupee\", \"es\": \"Rupia india\"}', 'INR', '₹'),
(64, '{\"en\": \"Iraqi dinar\", \"es\": \"Dinar iraquí\"}', 'IQD', 'ع.د'),
(65, '{\"en\": \"Iranian rial\", \"es\": \"Rial iraní\"}', 'IRR', 'ریال'),
(66, '{\"en\": \"Icelandic króna\", \"es\": \"Corona islandesa\"}', 'ISK', 'kr'),
(67, '{\"en\": \"Jamaican Dollar\", \"es\": \"Dólar Jamaiquino\"}', 'JMD', '$'),
(68, '{\"en\": \"Jordanian Dinar\", \"es\": \"Dinar Jordano\"}', 'JOD', 'د.ا'),
(69, '{\"en\": \"Japanese Yen\", \"es\": \"Yen japonés\"}', 'JPY', '¥'),
(70, '{\"en\": \"Kenyan Shilling\", \"es\": \"Chelín Keniano\"}', 'KES', 'KSh'),
(71, '{\"en\": \"Kyrgyzstani Som\", \"es\": \"Som kirguís\"}', 'KGS', 'с'),
(72, '{\"en\": \"Riel\", \"es\": \"Riel\"}', 'KHR', '៛'),
(73, '{\"en\": \"Comorian Franc\", \"es\": \"Franco comorano\"}', 'KMF', 'CF'),
(74, '{\"en\": \"North Korean Won\", \"es\": \"Won norcoreano\"}', 'KPW', '₩'),
(75, '{\"en\": \"South Korean Won\", \"es\": \"Won surcoreano\"}', 'KRW', '₩'),
(76, '{\"en\": \"Kuwaiti Dinar\", \"es\": \"Dinar Kuwaití\"}', 'KWD', 'د.ك'),
(77, '{\"en\": \"Cayman Islands Dollar\", \"es\": \"Dólar de las Islas Caimán\"}', 'KYD', '$'),
(78, '{\"en\": \"Kazakhstani Tenge\", \"es\": \"Tenge kazajo\"}', 'KZT', '₸'),
(79, '{\"en\": \"Lao Kip\", \"es\": \"Kip laosiano\"}', 'LAK', '₭'),
(80, '{\"en\": \"Lebanese Pound\", \"es\": \"Libra Libanesa\"}', 'LBP', 'ل.ل'),
(81, '{\"en\": \"Sri Lankan Rupee\", \"es\": \"Rupia de Sri Lanka\"}', 'LKR', 'රු'),
(82, '{\"en\": \"Liberian Dollar\", \"es\": \"Dólar Liberiano\"}', 'LRD', '$'),
(83, '{\"en\": \"Lesotho Loti\", \"es\": \"Loti de Lesotho\"}', 'LSL', 'M'),
(84, '{\"en\": \"Libyan Dinar\", \"es\": \"Dinar Libio\"}', 'LYD', 'د.ل'),
(85, '{\"en\": \"Moroccan Dirham\", \"es\": \"Dirham marroquí\"}', 'MAD', 'د.م.'),
(86, '{\"en\": \"Moldovan Leu\", \"es\": \"Leu Moldavo\"}', 'MDL', 'L'),
(87, '{\"en\": \"Malagasy Ariary\", \"es\": \"Ariary Malgache\"}', 'MGA', 'Ar'),
(88, '{\"en\": \"Macedonian Denar\", \"es\": \"Denar macedonio\"}', 'MKD', 'ден'),
(89, '{\"en\": \"Myanmar Kyat\", \"es\": \"Kyat de Birmania\"}', 'MMK', 'Ks'),
(90, '{\"en\": \"Mongolian Tugrik\", \"es\": \"Tugrik Mongol\"}', 'MNT', '₮'),
(91, '{\"en\": \"Macanese Pataca\", \"es\": \"Pataca Macanesa\"}', 'MOP', 'P'),
(92, '{\"en\": \"Mauritanian Ouguiya\", \"es\": \"Uguía Mauritano\"}', 'MRU', 'UM'),
(93, '{\"en\": \"Mauritian Rupee\", \"es\": \"Rupia Mauricio\"}', 'MUR', '₨'),
(94, '{\"en\": \"Maldivian Rufiyaa\", \"es\": \"Rufiyaa Maldivo\"}', 'MVR', 'Rf'),
(95, '{\"en\": \"Malawian Kwacha\", \"es\": \"Kwacha Malauí\"}', 'MWK', 'K'),
(96, '{\"en\": \"Mexican Peso\", \"es\": \"Peso Mexicano\"}', 'MXN', '$'),
(97, '{\"en\": \"Malaysian Ringgit\", \"es\": \"Ringgit Malayo\"}', 'MYR', 'RM'),
(98, '{\"en\": \"Mozambican Metical\", \"es\": \"Metical mozambiqueño\"}', 'MZN', 'MT'),
(99, '{\"en\": \"Namibian Dollar\", \"es\": \"Dólar namibio\"}', 'NAD', '$'),
(100, '{\"en\": \"Nigerian Naira\", \"es\": \"Naira nigeriana\"}', 'NGN', '₦'),
(101, '{\"en\": \"Nicaraguan Córdoba\", \"es\": \"Córdoba nicaragüense\"}', 'NIO', 'C$'),
(102, '{\"en\": \"Norwegian Krone\", \"es\": \"Corona noruega\"}', 'NOK', 'kr'),
(103, '{\"en\": \"Nepalese Rupee\", \"es\": \"Rupia nepalesa\"}', 'NPR', '₨'),
(104, '{\"en\": \"New Zealand Dollar\", \"es\": \"Dólar de Nueva Zelanda\"}', 'NZD', '$'),
(105, '{\"en\": \"Omani Rial\", \"es\": \"Rial Omaní\"}', 'OMR', 'ر.ع.'),
(106, '{\"en\": \"Panamanian Balboa\", \"es\": \"Balboa Panameño\"}', 'PAB', 'B/.'),
(107, '{\"en\": \"Peruvian Sol\", \"es\": \"Sol peruano\"}', 'PEN', 'S/'),
(108, '{\"en\": \"Papua New Guinean Kina\", \"es\": \"Kina de Papúa Nueva Guinea\"}', 'PGK', 'K'),
(109, '{\"en\": \"Philippine Peso\", \"es\": \"Peso Filipino\"}', 'PHP', '₱'),
(110, '{\"en\": \"Pakistani Rupee\", \"es\": \"Rupia Paquistaní\"}', 'PKR', '₨'),
(111, '{\"en\": \"Polish Zloty\", \"es\": \"Zloty Polaco\"}', 'PLN', 'zł'),
(112, '{\"en\": \"Paraguayan Guarani\", \"es\": \"Guaraní paraguayo\"}', 'PYG', '₲'),
(113, '{\"en\": \"Qatari Rial\", \"es\": \"Rial Qatarí\"}', 'QAR', 'ر.ق.'),
(114, '{\"en\": \"Romanian Leu\", \"es\": \"Leu Rumano\"}', 'RON', 'lei'),
(115, '{\"en\": \"Serbian dinar\", \"es\": \"Dinar serbio\"}', 'RSD', 'дин.'),
(116, '{\"en\": \"Russian Ruble\", \"es\": \"Rublo Ruso\"}', 'RUB', '₽'),
(117, '{\"en\": \"Rwandan Franc\", \"es\": \"Franco Ruandés\"}', 'RWF', 'FRw'),
(118, '{\"en\": \"Saudi riyal\", \"es\": \"Riyal saudí\"}', 'SAR', 'ر.س'),
(119, '{\"en\": \"Solomon Islands Dollar\", \"es\": \"Dólar de las Islas Salomón\"}', 'SBD', '$'),
(120, '{\"en\": \"Seychellois rupee\", \"es\": \"Rupia seychelense\"}', 'SCR', '₨'),
(121, '{\"en\": \"Sudanese Pound\", \"es\": \"Libra sudanesa\"}', 'SDG', '£'),
(122, '{\"en\": \"Swedish Krona\", \"es\": \"Corona sueca\"}', 'SEK', 'kr'),
(123, '{\"en\": \"Singapore dollar\", \"es\": \"Dólar de Singapur\"}', 'SGD', '$'),
(124, '{\"en\": \"Saint Helena pound\", \"es\": \"Libra de Santa Elena\"}', 'SHP', '£'),
(125, '{\"en\": \"Sierra Leonean leone\", \"es\": \"Leone de Sierra Leona\"}', 'SLL', 'Le'),
(126, '{\"en\": \"Somali Shilling\", \"es\": \"Chelín somalí\"}', 'SOS', 'Sh'),
(127, '{\"en\": \"Surinamese Dollar\", \"es\": \"Dólar surinamés\"}', 'SRD', '$'),
(128, '{\"en\": \"South Sudanese Pound\", \"es\": \"Libra sursudanesa\"}', 'SSP', '£'),
(129, '{\"en\": \"São Tomé and Príncipe dobra\", \"es\": \"Dobra de Santo Tomé y Príncipe\"}', 'STN', 'Db'),
(130, '{\"en\": \"Swazi Lilangeni\", \"es\": \"Lilangeni Suazi\"}', 'SZL', 'E'),
(131, '{\"en\": \"Syrian Pound\", \"es\": \"Libra siria\"}', 'SYP', '£'),
(132, '{\"en\": \"Tajikistani Somoni\", \"es\": \"Somoní tayiko\"}', 'TJS', 'SM'),
(133, '{\"en\": \"Turkmenistan Manat\", \"es\": \"Manat turcomano\"}', 'TMT', 'm'),
(134, '{\"en\": \"Tunisian Dinar\", \"es\": \"Dinar tunecino\"}', 'TND', 'د.ت'),
(135, '{\"en\": \"Tongan Paʻanga\", \"es\": \"Paʻanga tongano\"}', 'TOP', 'T$'),
(136, '{\"en\": \"Turkish Lira\", \"es\": \"Lira turca\"}', 'TRY', '₺'),
(137, '{\"en\": \"Trinidad and Tobago Dollar\", \"es\": \"Dólar de Trinidad y Tobago\"}', 'TTD', '$'),
(138, '{\"en\": \"New Taiwan Dollar\", \"es\": \"Nuevo dólar taiwanés\"}', 'TWD', 'NT$'),
(139, '{\"en\": \"Tanzanian Shilling\", \"es\": \"Chelín tanzano\"}', 'TZS', 'Sh'),
(140, '{\"en\": \"Ukrainian Hryvnia\", \"es\": \"Grivna ucraniana\"}', 'UAH', '₴'),
(141, '{\"en\": \"Ugandan Shilling\", \"es\": \"Chelín ugandés\"}', 'UGX', 'Sh'),
(142, '{\"en\": \"United States Dollar\", \"es\": \"Dólar estadounidense\"}', 'USD', '$'),
(143, '{\"en\": \"Uruguayan Peso\", \"es\": \"Peso uruguayo\"}', 'UYU', '$'),
(144, '{\"en\": \"Uzbekistani Som\", \"es\": \"Som uzbeko\"}', 'UZS', 'сум'),
(145, '{\"en\": \"Venezuelan Bolívar\", \"es\": \"Bolívar venezolano\"}', 'VES', 'Bs.'),
(146, '{\"en\": \"Vietnamese Đồng\", \"es\": \"Đồng vietnamita\"}', 'VND', '₫'),
(147, '{\"en\": \"Vanuatu Vatu\", \"es\": \"Vatu de Vanuatu\"}', 'VUV', 'Vt'),
(148, '{\"en\": \"Samoan Tala\", \"es\": \"Tala samoano\"}', 'WST', 'T'),
(149, '{\"en\": \"Central African CFA Franc\", \"es\": \"Franco CFA de África Central\"}', 'XAF', 'FCFA'),
(150, '{\"en\": \"East Caribbean Dollar\", \"es\": \"Dólar del Caribe Oriental\"}', 'XCD', '$'),
(151, '{\"en\": \"West African CFA Franc\", \"es\": \"Franco CFA de África Occidental\"}', 'XOF', '₣'),
(152, '{\"en\": \"CFP Franc\", \"es\": \"Franco CFP\"}', 'XPF', '₣'),
(153, '{\"en\": \"Yemeni Rial\", \"es\": \"Rial yemení\"}', 'YER', '﷼'),
(154, '{\"en\": \"South African Rand\", \"es\": \"Rand sudafricano\"}', 'ZAR', 'R'),
(155, '{\"en\": \"Zambian Kwacha\", \"es\": \"Kwacha zambiano\"}', 'ZMW', 'K'),
(156, '{\"en\": \"Zimbabwean Dollar\", \"es\": \"Dólar zimbabuense\"}', 'ZWL', '$'),
(157, '{\"en\": \"Thai Baht\", \"es\": \"Baht tailandés\"}', 'THB', '฿');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `data_flags`
--

CREATE TABLE `data_flags` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each flag.',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the flag or the country to which it belongs.',
  `emoji` varchar(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Flag emoji.',
  `location` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Partial or complete path of the location icon with the flag.',
  `flat_2d` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Partial or complete path of the flag in its original format, without details.',
  `rounded_2d` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Partial or complete path of the circular flag format, without additional details.',
  `wave_2d` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Partial or complete path of the flag with waves, simulating a real flag waving.',
  `flat_3d` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Partial or complete path of the flag in its original format, with details that make it appear 3D.',
  `rounded_3d` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Partial or complete path of the circular flag format, with details that make it appear 3D.',
  `wave_3d` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Partial or complete path of the circular flag format, with details that make it appear 3D and simulate a waving flag.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores information about country flags.';

--
-- Volcado de datos para la tabla `data_flags`
--

INSERT INTO `data_flags` (`id`, `name`, `emoji`, `location`, `flat_2d`, `rounded_2d`, `wave_2d`, `flat_3d`, `rounded_3d`, `wave_3d`) VALUES
(1, 'afghanistan', '🇦🇫', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(2, 'albania', '🇦🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(3, 'algeria', '🇩🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(4, 'american_samoa', '🇦🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(5, 'andorra', '🇦🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(6, 'angola', '🇦🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(7, 'anguilla', '🇬🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(8, 'antarctica', '🇦🇶', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(9, 'antigua_and_barbuda', '🇦🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(10, 'argentina', '🇦🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(11, 'armenia', '🇦🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(12, 'aruba', '🇦🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(13, 'ascension_island', '🇦🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(14, 'australia', '🇦🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(15, 'austria', '🇦🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(16, 'azerbaijan', '🇦🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(17, 'bahamas', '🇧🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(18, 'bahrain', '🇧🇭', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(19, 'bangladesh', '🇧🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(20, 'barbados', '🇧🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(21, 'belarus', '🇧🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(22, 'belgium', '🇧🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(23, 'belize', '🇧🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(24, 'benin', '🇧🇯', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(25, 'bermuda', '🇧🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(26, 'bhutan', '🇧🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(27, 'bolivia', '🇧🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(28, 'bonaire_sint_eustatius_and_saba', '🇧🇶', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(29, 'bosnia_and_herzegovina', '🇧🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(30, 'botswana', '🇧🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(31, 'brazil', '🇧🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(32, 'british_indian_ocean_territory', '🇮🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(33, 'brunei_darussalam', '🇧🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(34, 'bulgaria', '🇧🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(35, 'burkina_faso', '🇧🇫', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(36, 'burundi', '🇧🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(37, 'cape_verde', '🇨🇻', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(38, 'cambodia', '🇰🇭', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(39, 'cameroon', '🇨🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(40, 'canada', '🇨🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(41, 'cayman_islands', '🇰🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(42, 'central_african_republic', '🇨🇫', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(43, 'chad', '🇹🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(44, 'chile', '🇨🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(45, 'china', '🇨🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(46, 'christmas_island', '🇨🇽', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(47, 'cocos_keeling_islands', '🇨🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(48, 'colombia', '🇨🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(49, 'comoros', '🇰🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(50, 'cook_islands', '🇨🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(51, 'costa_rica', '🇨🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(52, 'croatia', '🇭🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(53, 'cuba', '🇨🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(54, 'curaao', '🇨🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(55, 'cyprus', '🇨🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(56, 'czech_republic', '🇨🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(57, 'cte_divoire', '🇮🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(58, 'democratic_republic_of_the_congo', '🇨🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(59, 'denmark', '🇩🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(60, 'diego_garcia', '🇮🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(61, 'djibouti', '🇩🇯', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(62, 'dominica', '🇩🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(63, 'dominican_republic', '🇩🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(64, 'ecuador', '🇪🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(65, 'egypt', '🇪🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(66, 'el_salvador', '🇸🇻', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(67, 'equatorial_guinea', '🇬🇶', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(68, 'eritrea', '🇪🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(69, 'estonia', '🇪🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(70, 'eswatini', '🇸🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(71, 'ethiopia', '🇪🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(72, 'falkland_islands', '🇫🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(73, 'faroe_islands', '🇫🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(74, 'micronesia', '🇫🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(75, 'fiji', '🇫🇯', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(76, 'finland', '🇫🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(77, 'france', '🇫🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(78, 'french_guiana', '🇬🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(79, 'french_polynesia', '🇵🇫', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(80, 'gabon', '🇬🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(81, 'gambia', '🇬🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(82, 'georgia', '🇬🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(83, 'germany', '🇩🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(84, 'ghana', '🇬🇭', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(85, 'gibraltar', '🇬🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(86, 'greece', '🇬🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(87, 'greenland', '🇬🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(88, 'grenada', '🇬🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(89, 'guadeloupe', '🇬🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(90, 'guam', '🇬🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(91, 'guatemala', '🇬🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(92, 'guernsey', '🇬🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(93, 'guinea', '🇬🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(94, 'guinea_bissau', '🇬🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(95, 'guyana', '🇬🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(96, 'haiti', '🇭🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(97, 'holy_see', '🇻🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(98, 'honduras', '🇭🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(99, 'hong_kong', '🇭🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(100, 'hungary', '🇭🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(101, 'iceland', '🇮🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(102, 'india', '🇮🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(103, 'indonesia', '🇮🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(104, 'iran', '🇮🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(105, 'iraq', '🇮🇶', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(106, 'ireland', '🇮🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(107, 'isle_of_man', '🇮🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(108, 'israel', '🇮🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(109, 'italy', '🇮🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(110, 'jamaica', '🇯🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(111, 'japan', '🇯🇵', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(112, 'jersey', '🇯🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(113, 'jordan', '🇯🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(114, 'kazakhstan', '🇰🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(115, 'kenya', '🇰🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(116, 'kiribati', '🇰🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(117, 'kosovo', '🇽🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(118, 'kuwait', '🇰🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(119, 'kyrgyzstan', '🇰🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(120, 'laos', '🇱🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(121, 'latvia', '🇱🇻', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(122, 'lebanon', '🇱🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(123, 'lesotho', '🇱🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(124, 'liberia', '🇱🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(125, 'libya', '🇱🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(126, 'liechtenstein', '🇱🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(127, 'lithuania', '🇱🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(128, 'luxembourg', '🇱🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(129, 'macau', '🇲🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(130, 'madagascar', '🇲🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(131, 'malawi', '🇲🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(132, 'malaysia', '🇲🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(133, 'maldives', '🇲🇻', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(134, 'mali', '🇲🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(135, 'malta', '🇲🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(136, 'marshall_islands', '🇲🇭', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(137, 'martinique', '🇲🇶', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(138, 'mauritania', '🇲🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(139, 'mauritius', '🇲🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(140, 'mayotte', '🇾🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(141, 'mexico', '🇲🇽', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(142, 'moldova', '🇲🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(143, 'monaco', '🇲🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(144, 'mongolia', '🇲🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(145, 'montenegro', '🇲🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(146, 'montserrat', '🇲🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(147, 'morocco', '🇲🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(148, 'mozambique', '🇲🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(149, 'myanmar', '🇲🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(150, 'namibia', '🇳🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(151, 'nauru', '🇳🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(152, 'nepal', '🇳🇵', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(153, 'netherlands', '🇳🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(154, 'new_caledonia', '🇳🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(155, 'new_zealand', '🇳🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(156, 'nicaragua', '🇳🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(157, 'niger', '🇳🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(158, 'nigeria', '🇳🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(159, 'niue', '🇳🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(160, 'norfolk_island', '🇳🇫', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(161, 'north_korea', '🇰🇵', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(162, 'north_macedonia', '🇲🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(163, 'northern_ireland', '🇬🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(164, 'northern_mariana_islands', '🇲🇵', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(165, 'norway', '🇳🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(166, 'oman', '🇴🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(167, 'pakistan', '🇵🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(168, 'palau', '🇵🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(169, 'panama', '🇵🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(170, 'papua_new_guinea', '🇵🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(171, 'paraguay', '🇵🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(172, 'peru', '🇵🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(173, 'philippines', '🇵🇭', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(174, 'pitcairn', '🇬🇵', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(175, 'poland', '🇵🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(176, 'portugal', '🇵🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(177, 'puerto_rico', '🇵🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(178, 'qatar', '🇶🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(179, 'republic_of_the_congo', '🇨🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(180, 'romania', '🇷🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(181, 'russia', '🇷🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(182, 'rwanda', '🇷🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(183, 'reunion', '🇷🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(184, 'saint_barthelemy', '🇧🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(185, 'saint_helena', '🇬🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(186, 'saint_helena_ascension_and_tristan_da_cunha', '🇬🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(187, 'saint_kitts_and_nevis', '🇰🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(188, 'saint_lucia', '🇱🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(189, 'saint_martin', '🇫🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(190, 'saint_pierre_and_miquelon', '🇫🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(191, 'saint_vincent_and_the_grenadines', '🇻🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(192, 'samoa', '🇼🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(193, 'san_marino', '🇸🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(194, 'sao_tome_and_principe', '🇸🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(195, 'saudi_arabia', '🇸🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(196, 'scotland', '🏴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(197, 'senegal', '🇸🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(198, 'serbia', '🇷🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(199, 'seychelles', '🇸🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(200, 'sierra_leone', '🇸🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(201, 'singapore', '🇸🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(202, 'sint_maarten', '🇸🇽', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(203, 'slovakia', '🇸🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(204, 'slovenia', '🇸🇮', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(205, 'solomon_islands', '🇸🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(206, 'somalia', '🇸🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(207, 'south_africa', '🇿🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(208, 'south_korea', '🇰🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(209, 'south_sudan', '🇸🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(210, 'spain', '🇪🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(211, 'sri_lanka', '🇱🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(212, 'state_of_palestine', '🇵🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(213, 'sudan', '🇸🇩', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(214, 'suriname', '🇸🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(215, 'sweden', '🇸🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(216, 'switzerland', '🇨🇭', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(217, 'syria', '🇸🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(218, 'taiwan', '🇹🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(219, 'tajikistan', '🇹🇯', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(220, 'tanzania', '🇹🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(221, 'thailand', '🇹🇭', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(222, 'timor_leste', '🇹🇱', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(223, 'togo', '🇹🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(224, 'tokelau', '🇹🇰', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(225, 'tonga', '🇹🇴', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(226, 'trinidad_and_tobago', '🇹🇹', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(227, 'tunisia', '🇹🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(228, 'turkmenistan', '🇹🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(229, 'turks_and_caicos_islands', '🇹🇨', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(230, 'tuvalu', '🇹🇻', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(231, 'turkiye', '🇹🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(232, 'uganda', '🇺🇬', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(233, 'ukraine', '🇺🇦', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(234, 'united_arab_emirates', '🇦🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(235, 'united_kingdom', '🇬🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(236, 'united_states_of_america', '🇺🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(237, 'uruguay', '🇺🇾', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(238, 'uzbekistan', '🇺🇿', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(239, 'vanuatu', '🇻🇺', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(240, 'venezuela', '🇻🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(241, 'vietnam', '🇻🇳', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(242, 'virgin_islands_british', '🇬🇧', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(243, 'virgin_islands_us', '🇺🇸', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(244, 'wallis_and_futuna', '🇫🇷', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(245, 'yemen', '🇾🇪', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(246, 'zambia', '🇿🇲', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(247, 'zimbabwe', '🇿🇼', NULL, NULL, NULL, NULL, NULL, NULL, NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `data_languages`
--

CREATE TABLE `data_languages` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each language.',
  `id_flag` int DEFAULT NULL COMMENT 'ID of the flag that will be displayed alongside the language.',
  `abbreviation` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Language abbreviation, typically used for internationalization libraries.',
  `version` varchar(4) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Version of the language for different parts of the world that speak the same language. This is completely optional.',
  `name` json NOT NULL COMMENT 'Name of the language, written in multiple languages for internationalization.',
  `description` json DEFAULT NULL COMMENT 'Explanatory description of the language, provided in English as it is the standard in software development.',
  `orientation` enum('L2R','R2L','T2BL2R','T2BR2L') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'L2R' COMMENT 'The language can have different writing orientations: left-to-right (L2R), right-to-left (R2L), top-to-bottom with left-to-right direction (T2BL2R), or top-to-bottom with right-to-left direction (T2BR2L).',
  `public` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether this is a selectable language to change the platform language.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the languages and their available versions.';

--
-- Volcado de datos para la tabla `data_languages`
--

INSERT INTO `data_languages` (`id`, `id_flag`, `abbreviation`, `version`, `name`, `description`, `orientation`, `public`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, NULL, 'af', NULL, '{\"en\": \"Afrikaans\", \"es\": \"Afrikaans\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(2, NULL, 'sq', NULL, '{\"en\": \"Albanian\", \"es\": \"Albanés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(3, NULL, 'am', NULL, '{\"en\": \"Amharic\", \"es\": \"Amárico\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(4, NULL, 'ar', NULL, '{\"en\": \"Arabic\", \"es\": \"Árabe\"}', NULL, 'R2L', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(5, NULL, 'hy', NULL, '{\"en\": \"Armenian\", \"es\": \"Armenio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(6, NULL, 'ay', NULL, '{\"en\": \"Aymara\", \"es\": \"Aymara\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(7, NULL, 'az', NULL, '{\"en\": \"Azerbaijani\", \"es\": \"Azerí\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(8, NULL, 'bm', NULL, '{\"en\": \"Bambara\", \"es\": \"Bambara\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(9, NULL, 'eu', NULL, '{\"en\": \"Basque\", \"es\": \"Vasco\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(10, NULL, 'be', NULL, '{\"en\": \"Belarusian\", \"es\": \"Bielorruso\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(11, NULL, 'bmb', NULL, '{\"en\": \"Bemba\", \"es\": \"Bemba\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(12, NULL, 'bn', NULL, '{\"en\": \"Bengali\", \"es\": \"Bengalí\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(13, NULL, 'ber', NULL, '{\"en\": \"Berber\", \"es\": \"Bereber\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(14, NULL, 'bho', NULL, '{\"en\": \"Bhojpuri\", \"es\": \"Bhojpuri\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(15, NULL, 'bi', NULL, '{\"en\": \"Bislama\", \"es\": \"Bislama\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(16, NULL, 'bs', NULL, '{\"en\": \"Bosnian\", \"es\": \"Bosnio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(17, NULL, 'bg', NULL, '{\"en\": \"Bulgarian\", \"es\": \"Búlgaro\"}', NULL, 'L2R', 0, '2025-01-20 22:23:58', '2025-01-20 22:23:58', NULL),
(18, NULL, 'my', NULL, '{\"en\": \"Burmese\", \"es\": \"Birmano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(19, NULL, 'ce', NULL, '{\"en\": \"Cape Verdean Creole\", \"es\": \"Criollo caboverdiano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(20, NULL, 'ca', NULL, '{\"en\": \"Catalan\", \"es\": \"Catalán\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(21, NULL, 'ch', NULL, '{\"en\": \"Chamorro\", \"es\": \"Chamorro\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(22, NULL, 'ny', NULL, '{\"en\": \"Chichewa\", \"es\": \"Chichewa\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(23, NULL, 'zh', NULL, '{\"en\": \"Chinese\", \"es\": \"Chino\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(24, NULL, 'zh', 'HK', '{\"en\": \"Chinese (Cantonese)\", \"es\": \"Chino (Cantonés)\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(25, NULL, 'co', NULL, '{\"en\": \"Comorian\", \"es\": \"Comoriano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(26, NULL, 'mi', NULL, '{\"en\": \"Cook Islands Maori\", \"es\": \"Maorí de las Islas Cook\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(27, NULL, 'crs', NULL, '{\"en\": \"Crioulo\", \"es\": \"Criollo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(28, NULL, 'hr', NULL, '{\"en\": \"Croatian\", \"es\": \"Croata\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(29, NULL, 'cs', NULL, '{\"en\": \"Czech\", \"es\": \"Checo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(30, NULL, 'da', NULL, '{\"en\": \"Danish\", \"es\": \"Danés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(31, NULL, 'fa', NULL, '{\"en\": \"Dari\", \"es\": \"Dari\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(32, NULL, 'dv', NULL, '{\"en\": \"Dhivehi\", \"es\": \"Dhivehi\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(33, NULL, 'dink', NULL, '{\"en\": \"Dinka\", \"es\": \"Dinka\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(34, NULL, 'di', NULL, '{\"en\": \"Dioula\", \"es\": \"Dioula\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(35, NULL, 'nl', NULL, '{\"en\": \"Dutch\", \"es\": \"Neerlandés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(36, NULL, 'dz', NULL, '{\"en\": \"Dzongkha\", \"es\": \"Dzongkha\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(37, NULL, 'en', NULL, '{\"en\": \"English\", \"es\": \"Inglés\"}', NULL, 'L2R', 1, '2025-01-20 22:23:59', '2025-01-20 22:24:40', NULL),
(38, NULL, 'et', NULL, '{\"en\": \"Estonian\", \"es\": \"Estonio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(39, NULL, 'ee', NULL, '{\"en\": \"Ewe\", \"es\": \"Ewe\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(40, NULL, 'fo', NULL, '{\"en\": \"Faroese\", \"es\": \"Feroés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(41, NULL, 'fj', NULL, '{\"en\": \"Fijian\", \"es\": \"Fijiano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(42, NULL, 'fil', NULL, '{\"en\": \"Filipino\", \"es\": \"Filipino\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(43, NULL, 'fi', NULL, '{\"en\": \"Finnish\", \"es\": \"Finlandés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(44, NULL, 'fr', NULL, '{\"en\": \"French\", \"es\": \"Francés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(45, NULL, 'ht', NULL, '{\"en\": \"Haitian Creole\", \"es\": \"Criollo haitiano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(46, NULL, 'fy', NULL, '{\"en\": \"Frisian\", \"es\": \"Frisio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(47, NULL, 'fut', NULL, '{\"en\": \"Futunan\", \"es\": \"Futunano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(48, NULL, 'gl', NULL, '{\"en\": \"Galician\", \"es\": \"Gallego\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(49, NULL, 'ka', NULL, '{\"en\": \"Georgian\", \"es\": \"Georgiano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(50, NULL, 'de', NULL, '{\"en\": \"German\", \"es\": \"Alemán\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(51, NULL, 'gil', NULL, '{\"en\": \"Gilbertese\", \"es\": \"Gilbertense\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(52, NULL, 'el', NULL, '{\"en\": \"Greek\", \"es\": \"Griego\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(53, NULL, 'kl', NULL, '{\"en\": \"Greenlandic\", \"es\": \"Verlandés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(54, NULL, 'gn', NULL, '{\"en\": \"Guarani\", \"es\": \"Guaraní\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(55, NULL, 'ha', NULL, '{\"en\": \"Haitian Creole\", \"es\": \"Criollo haitiano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(56, NULL, 'ha', NULL, '{\"en\": \"Hausa\", \"es\": \"Hausa\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(57, NULL, 'he', NULL, '{\"en\": \"Hebrew\", \"es\": \"Hebreo\"}', NULL, 'R2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(58, NULL, 'hz', NULL, '{\"en\": \"Herero\", \"es\": \"Herero\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(59, NULL, 'hi', NULL, '{\"en\": \"Hindi\", \"es\": \"Hindi\"}', NULL, 'R2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(60, NULL, 'hi', NULL, '{\"en\": \"Hindu\", \"es\": \"Hindu\"}', NULL, 'R2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(61, NULL, 'ho', NULL, '{\"en\": \"Hiri Motu\", \"es\": \"Hiri Motu\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(62, NULL, 'hu', NULL, '{\"en\": \"Hungarian\", \"es\": \"Húngaro\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(63, NULL, 'is', NULL, '{\"en\": \"Icelandic\", \"es\": \"Islandés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(64, NULL, 'ig', NULL, '{\"en\": \"Igbo\", \"es\": \"Igbo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(65, NULL, 'id', NULL, '{\"en\": \"Indonesian\", \"es\": \"Indonesio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(66, NULL, 'ga', NULL, '{\"en\": \"Irish\", \"es\": \"Irlandés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(67, NULL, 'it', NULL, '{\"en\": \"Italian\", \"es\": \"Italiano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(68, NULL, 'jm', NULL, '{\"en\": \"Jamaican Patois\", \"es\": \"Patois Jamaiquino\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(69, NULL, 'ja', NULL, '{\"en\": \"Japanese\", \"es\": \"Japonés\"}', NULL, 'T2BR2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(70, NULL, 'jv', NULL, '{\"en\": \"Javanese\", \"es\": \"Javanés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(71, NULL, 'jol', NULL, '{\"en\": \"Jola\", \"es\": \"Jola\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(72, NULL, 'fr', NULL, '{\"en\": \"Jèrriais\", \"es\": \"Jèrriais\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(73, NULL, 'qu', NULL, '{\"en\": \"K\'iche\", \"es\": \"K’iché\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(74, NULL, 'kab', NULL, '{\"en\": \"Kabiye\", \"es\": \"Kabiye\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(75, NULL, 'kan', NULL, '{\"en\": \"Kanak languages\", \"es\": \"Lenguas kanakas\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(76, NULL, 'kk', NULL, '{\"en\": \"Kazakh\", \"es\": \"Kazajo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(77, NULL, 'km', NULL, '{\"en\": \"Khmer\", \"es\": \"Jemer\"}', NULL, 'T2BR2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(78, NULL, 'kj', NULL, '{\"en\": \"Khoekhoe\", \"es\": \"Khoekhoe\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(79, NULL, 'kg', NULL, '{\"en\": \"Kikongo\", \"es\": \"Kikongo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(80, NULL, 'rw', NULL, '{\"en\": \"Kinyarwanda\", \"es\": \"Kinyarwanda\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(81, NULL, 'rn', NULL, '{\"en\": \"Kirundi\", \"es\": \"Kirundi\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(82, NULL, 'kg', NULL, '{\"en\": \"Kituba\", \"es\": \"Kituba\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(83, NULL, 'ko', NULL, '{\"en\": \"Korean\", \"es\": \"Coreano\"}', NULL, 'T2BR2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(84, NULL, 'kr', NULL, '{\"en\": \"Krio\", \"es\": \"Krio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(85, NULL, 'ku', NULL, '{\"en\": \"Kurdish\", \"es\": \"Kurdo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(86, NULL, 'kw', NULL, '{\"en\": \"Kwéyòl\", \"es\": \"Kwéyòl\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(87, NULL, 'ky', NULL, '{\"en\": \"Kyrgyz\", \"es\": \"Kirguís\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(88, NULL, 'lo', NULL, '{\"en\": \"Lao\", \"es\": \"Laosiano\"}', NULL, 'T2BR2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(89, NULL, 'la', NULL, '{\"en\": \"Latin\", \"es\": \"Latín\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(90, NULL, 'lv', NULL, '{\"en\": \"Latvian\", \"es\": \"Letón\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(91, NULL, 'lb', NULL, '{\"en\": \"Limba\", \"es\": \"Limba\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(92, NULL, 'ln', NULL, '{\"en\": \"Lingala\", \"es\": \"Lingala\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(93, NULL, 'lt', NULL, '{\"en\": \"Lithuanian\", \"es\": \"Lituano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(94, NULL, 'lb', NULL, '{\"en\": \"Luxembourgish\", \"es\": \"Luxemburgués\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(95, NULL, 'mk', NULL, '{\"en\": \"Macedonian\", \"es\": \"Macedonio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(96, NULL, 'mai', NULL, '{\"en\": \"Maithili\", \"es\": \"Maithili\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(97, NULL, 'mg', NULL, '{\"en\": \"Malagasy\", \"es\": \"Malgache\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(98, NULL, 'ms', NULL, '{\"en\": \"Malay\", \"es\": \"Malayo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(99, NULL, 'mt', NULL, '{\"en\": \"Maltese\", \"es\": \"Maltés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(100, NULL, 'zh', NULL, '{\"en\": \"Mandarin\", \"es\": \"Mandarín\"}', NULL, 'T2BR2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(101, NULL, 'mn', NULL, '{\"en\": \"Mandinka\", \"es\": \"Mandinga\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(102, NULL, 'gv', NULL, '{\"en\": \"Manx\", \"es\": \"Manx\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(103, NULL, 'mr', NULL, '{\"en\": \"Marathi\", \"es\": \"Marathi\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(104, NULL, 'mh', NULL, '{\"en\": \"Marshallese\", \"es\": \"Marshalés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(105, NULL, 'mfe', NULL, '{\"en\": \"Mauritian Creole\", \"es\": \"Criollo Mauriciano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(106, NULL, 'men', NULL, '{\"en\": \"Mende\", \"es\": \"Mende\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(107, NULL, 'mn', NULL, '{\"en\": \"Mongolian\", \"es\": \"Mongol\"}', NULL, 'R2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(108, NULL, 'me', NULL, '{\"en\": \"Montenegrin\", \"es\": \"Montenegrino\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(109, NULL, 'mi', NULL, '{\"en\": \"Māori\", \"es\": \"Māori\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(110, NULL, 'nr', NULL, '{\"en\": \"Nauruan\", \"es\": \"Nauruano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(111, NULL, 'ne', NULL, '{\"en\": \"Nepali\", \"es\": \"Nepalí\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(112, NULL, 'nzsl', NULL, '{\"en\": \"New Zealand Sign Language\", \"es\": \"Lengua de Señas de Nueva Zelanda\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(113, NULL, 'niu', NULL, '{\"en\": \"Niuean\", \"es\": \"Niueano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(114, NULL, 'none', NULL, '{\"en\": \"None\", \"es\": \"Ninguno\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(115, NULL, 'nf', NULL, '{\"en\": \"Norfolk\", \"es\": \"Norfolk\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(116, NULL, 'no', NULL, '{\"en\": \"Norwegian\", \"es\": \"Noruego\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(117, NULL, 'ss', NULL, '{\"en\": \"Nuer\", \"es\": \"Nuer\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(118, NULL, 'ny', NULL, '{\"en\": \"Nyanja\", \"es\": \"Nyanja\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(119, NULL, 'om', NULL, '{\"en\": \"Oromo\", \"es\": \"Oromo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(120, NULL, 'oj', NULL, '{\"en\": \"Oshiwambo\", \"es\": \"Oshiwambo\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(121, NULL, 'pau', NULL, '{\"en\": \"Palauan\", \"es\": \"Palauano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(122, NULL, 'pap', NULL, '{\"en\": \"Papiamento\", \"es\": \"Papiamento\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(123, NULL, 'ps', NULL, '{\"en\": \"Pashto\", \"es\": \"Pastún\"}', NULL, 'R2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(124, NULL, 'fa', NULL, '{\"en\": \"Persian\", \"es\": \"Persa\"}', NULL, 'R2L', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(125, NULL, 'pi', NULL, '{\"en\": \"Pitkern\", \"es\": \"Pitkern\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(126, NULL, 'pl', NULL, '{\"en\": \"Polish\", \"es\": \"Polaco\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(127, NULL, 'pt', NULL, '{\"en\": \"Portuguese\", \"es\": \"Portugués\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(128, NULL, 'pt', 'br', '{\"en\": \"Brazilian Portuguese\", \"es\": \"Portugués Brasileño\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(129, NULL, 'pul', NULL, '{\"en\": \"Pulaar\", \"es\": \"Pulaar\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(130, NULL, 'pa', NULL, '{\"en\": \"Punjabi\", \"es\": \"Punjabi\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(131, NULL, 'qce', NULL, '{\"en\": \"Q\'eqchi\", \"es\": \"Q’eqchi\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(132, NULL, 'qu', NULL, '{\"en\": \"Quechua\", \"es\": \"Quechua\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(133, NULL, 'ro', NULL, '{\"en\": \"Romanian\", \"es\": \"Rumano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(134, NULL, 'rm', NULL, '{\"en\": \"Romansh\", \"es\": \"Romanche\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(135, NULL, 'ru', NULL, '{\"en\": \"Russian\", \"es\": \"Ruso\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(136, NULL, 'sm', NULL, '{\"en\": \"Samoan\", \"es\": \"Samoano\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(137, NULL, 'sg', NULL, '{\"en\": \"Sango\", \"es\": \"Sango\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(138, NULL, 'gd', NULL, '{\"en\": \"Scots\", \"es\": \"Escocés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(139, NULL, 'gd', NULL, '{\"en\": \"Scottish Gaelic\", \"es\": \"Gaélico Escocés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(140, NULL, 'sr', NULL, '{\"en\": \"Serbian\", \"es\": \"Serbio\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(141, NULL, 'sh', NULL, '{\"en\": \"Serbo-Croatian\", \"es\": \"Serbocroata\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(142, NULL, 'st', NULL, '{\"en\": \"Sesotho\", \"es\": \"Sesotho\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(143, NULL, 'tn', NULL, '{\"en\": \"Setswana\", \"es\": \"Setswana\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(144, NULL, 'sc', NULL, '{\"en\": \"Seychellois Creole\", \"es\": \"Criollo de Seychelles\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(145, NULL, 'sn', NULL, '{\"en\": \"Shona\", \"es\": \"Shona\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(146, NULL, 'nd', NULL, '{\"en\": \"Sindebele\", \"es\": \"Sindebele\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(147, NULL, 'sd', NULL, '{\"en\": \"Sindhi\", \"es\": \"Sindhi\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(148, NULL, 'si', NULL, '{\"en\": \"Sinhala\", \"es\": \"Cingalés\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(149, NULL, 'sk', NULL, '{\"en\": \"Slovak\", \"es\": \"Eslovaco\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(150, NULL, 'sl', NULL, '{\"en\": \"Slovene\", \"es\": \"Esloveno\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(151, NULL, 'sb', NULL, '{\"en\": \"Solomon Islands Pijin\", \"es\": \"Pijin de las Islas Salomón\"}', NULL, 'L2R', 0, '2025-01-20 22:23:59', '2025-01-20 22:23:59', NULL),
(152, NULL, 'so', NULL, '{\"en\": \"Somali\", \"es\": \"Somalí\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(153, NULL, 'st', NULL, '{\"en\": \"Southern Sotho\", \"es\": \"Sotho del sur\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(154, NULL, 'es', NULL, '{\"en\": \"Spanish\", \"es\": \"Español\"}', NULL, 'L2R', 1, '2025-01-20 22:24:00', '2025-01-20 22:24:41', NULL),
(155, NULL, 'sr', NULL, '{\"en\": \"Sranan Tongo\", \"es\": \"Sranan Tongo\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(156, NULL, 'sw', NULL, '{\"en\": \"Swahili\", \"es\": \"Suajili\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(157, NULL, 'ss', NULL, '{\"en\": \"Swati\", \"es\": \"Swati\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(158, NULL, 'sv', NULL, '{\"en\": \"Swedish\", \"es\": \"Sueco\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(159, NULL, 'ty', NULL, '{\"en\": \"Tahitian\", \"es\": \"Tahitiano\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(160, NULL, 'tg', NULL, '{\"en\": \"Tajik\", \"es\": \"Tayiko\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(161, NULL, 'ta', NULL, '{\"en\": \"Tamil\", \"es\": \"Tamil\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(162, NULL, 'te', NULL, '{\"en\": \"Telugu\", \"es\": \"Telugu\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(163, NULL, 'tm', NULL, '{\"en\": \"Temne\", \"es\": \"Temne\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(164, NULL, 'tet', NULL, '{\"en\": \"Tetum\", \"es\": \"Tetum\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(165, NULL, 'th', NULL, '{\"en\": \"Thai\", \"es\": \"Tailandés\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(166, NULL, 'tr', NULL, '{\"en\": \"Tharu\", \"es\": \"Tharu\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(167, NULL, 'ti', NULL, '{\"en\": \"Tigrinya\", \"es\": \"Tigrinya\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(168, NULL, 'tpi', NULL, '{\"en\": \"Tok Pisin\", \"es\": \"Tok Pisin\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(169, NULL, 'tk', NULL, '{\"en\": \"Tokelauan\", \"es\": \"Tokelauano\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(170, NULL, 'to', NULL, '{\"en\": \"Tongan\", \"es\": \"Tonganés\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(171, NULL, 'ts', NULL, '{\"en\": \"Tshiluba\", \"es\": \"Tshiluba\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(172, NULL, 'tr', NULL, '{\"en\": \"Turkish\", \"es\": \"Turco\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(173, NULL, 'tkm', NULL, '{\"en\": \"Turkmen\", \"es\": \"Turcomano\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(174, NULL, 'tv', NULL, '{\"en\": \"Tuvaluan\", \"es\": \"Tuvaluano\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(175, NULL, 'uk', NULL, '{\"en\": \"Ukrainian\", \"es\": \"Ucraniano\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(176, NULL, 'ur', NULL, '{\"en\": \"Urdu\", \"es\": \"Urdu\"}', NULL, 'R2L', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(177, NULL, 'uz', NULL, '{\"en\": \"Uzbek\", \"es\": \"Uzbeco\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(178, NULL, 'vi', NULL, '{\"en\": \"Vietnamese\", \"es\": \"Vietnamita\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(179, NULL, 'wls', NULL, '{\"en\": \"Wallisian\", \"es\": \"Wallisiano\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(180, NULL, 'wo', NULL, '{\"en\": \"Wolof\", \"es\": \"Wólof\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(181, NULL, 'xh', NULL, '{\"en\": \"Xhosa\", \"es\": \"Xhosa\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(182, NULL, 'yo', NULL, '{\"en\": \"Yoruba\", \"es\": \"Yoruba\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(183, NULL, 'za', NULL, '{\"en\": \"Zarma\", \"es\": \"Zarma\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL),
(184, NULL, 'zu', NULL, '{\"en\": \"Zulu\", \"es\": \"Zulú\"}', NULL, 'L2R', 0, '2025-01-20 22:24:00', '2025-01-20 22:24:00', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `data_timezones`
--

CREATE TABLE `data_timezones` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each time zone.',
  `id_continent` int NOT NULL COMMENT 'ID of the continent to which the time zone belongs. This facilitates more efficient filtering of the required time zones.',
  `name` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'International name or identifier of the time zone (in "Continent/Zone" format).',
  `utc` varchar(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Coordinated Universal Time (UTC) offset of each time zone.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores time zones.';

--
-- Volcado de datos para la tabla `data_timezones`
--

INSERT INTO `data_timezones` (`id`, `id_continent`, `name`, `utc`) VALUES
(1, 1, 'Africa/Abidjan', '-05:00'),
(2, 1, 'Africa/Accra', '-05:00'),
(3, 1, 'Africa/Addis_Ababa', '+03:00'),
(4, 1, 'Africa/Algiers', '+01:00'),
(5, 1, 'Africa/Asmara', '+03:00'),
(6, 1, 'Africa/Bamako', '-05:00'),
(7, 1, 'Africa/Bangui', '+01:00'),
(8, 1, 'Africa/Banjul', '-05:00'),
(9, 1, 'Africa/Bissau', '-05:00'),
(10, 1, 'Africa/Blantyre', '+02:00'),
(11, 1, 'Africa/Brazzaville', '+01:00'),
(12, 1, 'Africa/Bujumbura', '+02:00'),
(13, 1, 'Africa/Cairo', '+02:00'),
(14, 1, 'Africa/Casablanca', '-05:00'),
(15, 1, 'Africa/Ceuta', '+01:00'),
(16, 1, 'Africa/Conakry', '-05:00'),
(17, 1, 'Africa/Dakar', '-05:00'),
(18, 1, 'Africa/Dar_es_Salaam', '+03:00'),
(19, 1, 'Africa/Djibouti', '+03:00'),
(20, 1, 'Africa/Douala', '+01:00'),
(21, 1, 'Africa/El_Aaiun', '-05:00'),
(22, 1, 'Africa/Freetown', '-05:00'),
(23, 1, 'Africa/Gaborone', '+02:00'),
(24, 1, 'Africa/Harare', '+02:00'),
(25, 1, 'Africa/Johannesburg', '+02:00'),
(26, 1, 'Africa/Juba', '+03:00'),
(27, 1, 'Africa/Kampala', '+03:00'),
(28, 1, 'Africa/Khartoum', '+02:00'),
(29, 1, 'Africa/Kigali', '+02:00'),
(30, 1, 'Africa/Kinshasa', '+01:00'),
(31, 1, 'Africa/Lagos', '+01:00'),
(32, 1, 'Africa/Libreville', '+01:00'),
(33, 1, 'Africa/Lome', '-05:00'),
(34, 1, 'Africa/Luanda', '+01:00'),
(35, 1, 'Africa/Lubumbashi', '+02:00'),
(36, 1, 'Africa/Lusaka', '+02:00'),
(37, 1, 'Africa/Malabo', '+01:00'),
(38, 1, 'Africa/Maputo', '+02:00'),
(39, 1, 'Africa/Maseru', '+02:00'),
(40, 1, 'Africa/Mbabane', '+02:00'),
(41, 1, 'Africa/Mogadishu', '+03:00'),
(42, 1, 'Africa/Monrovia', '-05:00'),
(43, 1, 'Africa/Nairobi', '+03:00'),
(44, 1, 'Africa/Ndjamena', '+01:00'),
(45, 1, 'Africa/Niamey', '+01:00'),
(46, 1, 'Africa/Nouakchott', '-05:00'),
(47, 1, 'Africa/Ouagadougou', '-05:00'),
(48, 1, 'Africa/Porto-Novo', '+01:00'),
(49, 1, 'Africa/Sao_Tome', '-05:00'),
(50, 1, 'Africa/Tripoli', '+02:00'),
(51, 1, 'Africa/Tunis', '+01:00'),
(52, 1, 'Africa/Windhoek', '+02:00'),
(53, 2, 'America/Adak', '-10:00'),
(54, 2, 'America/Anchorage', '-09:00'),
(55, 2, 'America/Anguilla', '-04:00'),
(56, 2, 'America/Antigua', '-04:00'),
(57, 2, 'America/Araguaina', '-03:00'),
(58, 2, 'America/Argentina/Buenos_Aires', '-03:00'),
(59, 2, 'America/Argentina/Catamarca', '-03:00'),
(60, 2, 'America/Argentina/Cordoba', '-03:00'),
(61, 2, 'America/Argentina/Jujuy', '-03:00'),
(62, 2, 'America/Argentina/La_Rioja', '-03:00'),
(63, 2, 'America/Argentina/Mendoza', '-03:00'),
(64, 2, 'America/Argentina/Rio_Gallegos', '-03:00'),
(65, 2, 'America/Argentina/Salta', '-03:00'),
(66, 2, 'America/Argentina/San_Juan', '-03:00'),
(67, 2, 'America/Argentina/San_Luis', '-03:00'),
(68, 2, 'America/Argentina/Tucuman', '-03:00'),
(69, 2, 'America/Argentina/Ushuaia', '-03:00'),
(70, 2, 'America/Aruba', '-04:00'),
(71, 2, 'America/Asuncion', '-04:00'),
(72, 2, 'America/Atikokan', '-05:00'),
(73, 2, 'America/Bahia', '-03:00'),
(74, 2, 'America/Bahia_Banderas', '-06:00'),
(75, 2, 'America/Barbados', '-04:00'),
(76, 2, 'America/Belem', '-03:00'),
(77, 2, 'America/Belize', '-06:00'),
(78, 2, 'America/Blanc-Sablon', '-04:00'),
(79, 2, 'America/Boa_Vista', '-04:00'),
(80, 2, 'America/Bogota', '-05:00'),
(81, 2, 'America/Boise', '-06:00'),
(82, 2, 'America/Cambridge_Bay', '-06:00'),
(83, 2, 'America/Campo_Grande', '-04:00'),
(84, 2, 'America/Cancun', '-05:00'),
(85, 2, 'America/Caracas', '-04:00'),
(86, 2, 'America/Cayenne', '-03:00'),
(87, 2, 'America/Cayman', '-05:00'),
(88, 2, 'America/Chicago', '-05:00'),
(89, 2, 'America/Chihuahua', '-07:00'),
(90, 2, 'America/Costa_Rica', '-06:00'),
(91, 2, 'America/Creston', '-07:00'),
(92, 2, 'America/Cuiaba', '-04:00'),
(93, 2, 'America/Curacao', '-04:00'),
(94, 2, 'America/Danmarkshavn', '-05:00'),
(95, 2, 'America/Dawson', '-07:00'),
(96, 2, 'America/Dawson_Creek', '-07:00'),
(97, 2, 'America/Denver', '-06:00'),
(98, 2, 'America/Detroit', '-04:00'),
(99, 2, 'America/Dominica', '-04:00'),
(100, 2, 'America/Edmonton', '-06:00'),
(101, 2, 'America/Eirunepe', '-05:00'),
(102, 2, 'America/El_Salvador', '-06:00'),
(103, 2, 'America/Fort_Nelson', '-07:00'),
(104, 2, 'America/Fortaleza', '-03:00'),
(105, 2, 'America/Glace_Bay', '-03:00'),
(106, 2, 'America/Godthab', '-02:00'),
(107, 2, 'America/Goose_Bay', '-03:00'),
(108, 2, 'America/Grand_Turk', '-04:00'),
(109, 2, 'America/Grenada', '-04:00'),
(110, 2, 'America/Guadeloupe', '-04:00'),
(111, 2, 'America/Guatemala', '-06:00'),
(112, 2, 'America/Guayaquil', '-05:00'),
(113, 2, 'America/Guyana', '-04:00'),
(114, 2, 'America/Halifax', '-03:00'),
(115, 2, 'America/Havana', '-04:00'),
(116, 2, 'America/Hermosillo', '-07:00'),
(117, 2, 'America/Indiana/Indianapolis', '-04:00'),
(118, 2, 'America/Indiana/Knox', '-05:00'),
(119, 2, 'America/Indiana/Marengo', '-04:00'),
(120, 2, 'America/Indiana/Petersburg', '-04:00'),
(121, 2, 'America/Indiana/Tell_City', '-05:00'),
(122, 2, 'America/Indiana/Vevay', '-04:00'),
(123, 2, 'America/Indiana/Vincennes', '-04:00'),
(124, 2, 'America/Indiana/Winamac', '-04:00'),
(125, 2, 'America/Inuvik', '-06:00'),
(126, 2, 'America/Iqaluit', '-04:00'),
(127, 2, 'America/Jamaica', '-05:00'),
(128, 2, 'America/Juneau', '-08:00'),
(129, 2, 'America/Kentucky/Louisville', '-04:00'),
(130, 2, 'America/Kentucky/Monticello', '-04:00'),
(131, 2, 'America/Kralendijk', '-04:00'),
(132, 2, 'America/La_Paz', '-04:00'),
(133, 2, 'America/Lima', '-05:00'),
(134, 2, 'America/Los_Angeles', '-07:00'),
(135, 2, 'America/Lower_Princes', '-04:00'),
(136, 2, 'America/Maceio', '-03:00'),
(137, 2, 'America/Managua', '-06:00'),
(138, 2, 'America/Manaus', '-04:00'),
(139, 2, 'America/Marigot', '-04:00'),
(140, 2, 'America/Martinique', '-04:00'),
(141, 2, 'America/Matamoros', '-05:00'),
(142, 2, 'America/Mazatlan', '-06:00'),
(143, 2, 'America/Menominee', '-05:00'),
(144, 2, 'America/Merida', '-05:00'),
(145, 2, 'America/Metlakatla', '-08:00'),
(146, 2, 'America/Mexico_City', '-05:00'),
(147, 2, 'America/Miquelon', '-02:00'),
(148, 2, 'Atlantic/Azoresd', '-05:00'),
(149, 2, 'Atlantic/Bermudad', '-03:00'),
(150, 2, 'Atlantic/Canaryd', '-05:00'),
(151, 2, 'Atlantic/Cape_Verde', '-01:00'),
(152, 2, 'Atlantic/Faroed', '-05:00'),
(153, 2, 'Atlantic/Madeirad', '-05:00'),
(154, 2, 'Atlantic/Reykjavikd', '-05:00'),
(155, 2, 'Atlantic/South_Georgia', '-02:00'),
(156, 2, 'Atlantic/St_Helenad', '-05:00'),
(157, 2, 'Atlantic/Stanley', '-03:00'),
(158, 2, 'Pacific/Galapagos', '-06:00'),
(159, 2, 'Pacific/Honolulu', '-10:00'),
(160, 3, 'Antarctica/Casey', '+08:00'),
(161, 3, 'Antarctica/Davis', '+07:00'),
(162, 3, 'Antarctica/DumontDUrville', '+10:00'),
(163, 3, 'Antarctica/Macquarie', '+11:00'),
(164, 3, 'Antarctica/Mawson', '+05:00'),
(165, 3, 'Antarctica/McMurdo', '+12:00'),
(166, 3, 'Antarctica/Palmer', '-03:00'),
(167, 3, 'Antarctica/Rothera', '-03:00'),
(168, 3, 'Antarctica/Syowa', '+03:00'),
(169, 3, 'Antarctica/Troll', '-05:00'),
(170, 3, 'Antarctica/Vostok', '+06:00'),
(171, 3, 'Arctic/Longyearbyen', '+01:00'),
(172, 4, 'Asia/Aden', '+03:00'),
(173, 4, 'Asia/Almaty', '+06:00'),
(174, 4, 'Asia/Amman', '+03:00'),
(175, 4, 'Asia/Anadyr', '+12:00'),
(176, 4, 'Asia/Aqtau', '+05:00'),
(177, 4, 'Asia/Aqtobe', '+05:00'),
(178, 4, 'Asia/Ashgabat', '+05:00'),
(179, 4, 'Asia/Atyrau', '+05:00'),
(180, 4, 'Asia/Baghdad', '+03:00'),
(181, 4, 'Asia/Bahrain', '+03:00'),
(182, 4, 'Asia/Baku', '+04:00'),
(183, 4, 'Asia/Bangkok', '+07:00'),
(184, 4, 'Asia/Barnaul', '+07:00'),
(185, 4, 'Asia/Beirut', '+03:00'),
(186, 4, 'Asia/Bishkek', '+06:00'),
(187, 4, 'Asia/Brunei', '+08:00'),
(188, 4, 'Asia/Chita', '+09:00'),
(189, 4, 'Asia/Choibalsan', '+08:00'),
(190, 4, 'Asia/Colombo', '+05:30'),
(191, 4, 'Asia/Damascus', '+03:00'),
(192, 4, 'Asia/Dhaka', '+06:00'),
(193, 4, 'Asia/Dili', '+09:00'),
(194, 4, 'Asia/Dubai', '+04:00'),
(195, 4, 'Asia/Dushanbe', '+05:00'),
(196, 4, 'Asia/Famagusta', '+03:00'),
(197, 4, 'Asia/Gaza', '+03:00'),
(198, 4, 'Asia/Hebron', '+03:00'),
(199, 4, 'Asia/Ho_Chi_Minh', '+07:00'),
(200, 4, 'Asia/Hong_Kong', '+08:00'),
(201, 4, 'Asia/Hovd', '+07:00'),
(202, 4, 'Asia/Irkutsk', '+08:00'),
(203, 4, 'Asia/Jakarta', '+07:00'),
(204, 4, 'Asia/Jayapura', '+09:00'),
(205, 4, 'Asia/Jerusalem', '+03:00'),
(206, 4, 'Asia/Kabul', '+04:30'),
(207, 4, 'Asia/Kamchatka', '+12:00'),
(208, 4, 'Asia/Karachi', '+05:00'),
(209, 4, 'Asia/Kathmandu', '+05:45'),
(210, 4, 'Asia/Khandyga', '+09:00'),
(211, 4, 'Asia/Kolkata', '+05:30'),
(212, 4, 'Asia/Krasnoyarsk', '+07:00'),
(213, 4, 'Asia/Kuala_Lumpur', '+08:00'),
(214, 4, 'Asia/Kuching', '+08:00'),
(215, 4, 'Asia/Kuwait', '+03:00'),
(216, 4, 'Asia/Macau', '+08:00'),
(217, 4, 'Asia/Magadan', '+11:00'),
(218, 4, 'Asia/Makassar', '+08:00'),
(219, 4, 'Asia/Manila', '+08:00'),
(220, 4, 'Asia/Muscat', '+04:00'),
(221, 4, 'Asia/Nicosia', '+03:00'),
(222, 4, 'Asia/Novokuznetsk', '+07:00'),
(223, 4, 'Asia/Novosibirsk', '+07:00'),
(224, 4, 'Asia/Omsk', '+06:00'),
(225, 4, 'Asia/Oral', '+05:00'),
(226, 4, 'Asia/Phnom_Penh', '+07:00'),
(227, 4, 'Asia/Pontianak', '+07:00'),
(228, 4, 'Asia/Pyongyang', '+09:00'),
(229, 4, 'Asia/Qatar', '+03:00'),
(230, 4, 'Asia/Qostanay', '+06:00'),
(231, 4, 'Asia/Qyzylorda', '+05:00'),
(232, 4, 'Asia/Riyadh', '+03:00'),
(233, 4, 'Asia/Sakhalin', '+11:00'),
(234, 4, 'Asia/Samarkand', '+05:00'),
(235, 4, 'Asia/Seoul', '+09:00'),
(236, 4, 'Asia/Shanghai', '+08:00'),
(237, 4, 'Asia/Singapore', '+08:00'),
(238, 4, 'Asia/Srednekolymsk', '+11:00'),
(239, 4, 'Asia/Taipei', '+08:00'),
(240, 4, 'Asia/Tashkent', '+05:00'),
(241, 4, 'Asia/Tbilisi', '+04:00'),
(242, 4, 'Asia/Tehran', '+04:30'),
(243, 4, 'Asia/Thimphu', '+06:00'),
(244, 4, 'Asia/Tokyo', '+09:00'),
(245, 4, 'Asia/Tomsk', '+07:00'),
(246, 4, 'Asia/Ulaanbaatar', '+08:00'),
(247, 4, 'Asia/Urumqi', '+06:00'),
(248, 4, 'Asia/Ust-Nera', '+10:00'),
(249, 4, 'Asia/Vientiane', '+07:00'),
(250, 4, 'Asia/Vladivostok', '+10:00'),
(251, 4, 'Asia/Yakutsk', '+09:00'),
(252, 4, 'Asia/Yangon', '+06:30'),
(253, 4, 'Asia/Yekaterinburg', '+05:00'),
(254, 4, 'Asia/Yerevan', '+04:00'),
(255, 4, 'Indian/Antananarivo', '+03:00'),
(256, 4, 'Indian/Chagos', '+06:00'),
(257, 4, 'Indian/Christmas', '+07:00'),
(258, 4, 'Indian/Cocos', '+06:30'),
(259, 4, 'Indian/Comoro', '+03:00'),
(260, 4, 'Indian/Kerguelen', '+05:00'),
(261, 4, 'Indian/Mahe', '+04:00'),
(262, 4, 'Indian/Maldives', '+05:00'),
(263, 4, 'Indian/Mauritius', '+04:00'),
(264, 4, 'Indian/Mayotte', '+03:00'),
(265, 4, 'Indian/Reunion', '+04:00'),
(266, 4, 'Pacific/Chuuk', '+10:00'),
(267, 4, 'Pacific/Efate', '+11:00'),
(268, 4, 'Pacific/Fiji', '+12:00'),
(269, 4, 'Pacific/Funafuti', '+12:00'),
(270, 4, 'Pacific/Guadalcanal', '+11:00'),
(271, 4, 'Pacific/Guam', '+10:00'),
(272, 4, 'Pacific/Kiritimati', '+14:00'),
(273, 4, 'Pacific/Kosrae', '+11:00'),
(274, 4, 'Pacific/Kwajalein', '+12:00'),
(275, 4, 'Pacific/Majuro', '+12:00'),
(276, 4, 'Pacific/Marquesas', '-09:30'),
(277, 4, 'Pacific/Nauru', '+12:00'),
(278, 4, 'Pacific/Niue', '-11:00'),
(279, 4, 'Pacific/Norfolk', '+11:00'),
(280, 4, 'Pacific/Noumea', '+11:00'),
(281, 4, 'Pacific/Pago_Pago', '-11:00'),
(282, 4, 'Pacific/Palau', '+09:00'),
(283, 4, 'Pacific/Pitcairn', '-08:00'),
(284, 4, 'Pacific/Pohnpei', '+11:00'),
(285, 4, 'Pacific/Port_Moresby', '+10:00'),
(286, 4, 'Pacific/Rarotonga', '-10:00'),
(287, 4, 'Pacific/Tahiti', '-10:00'),
(288, 4, 'Pacific/Tarawa', '+12:00'),
(289, 4, 'Pacific/Tongatapu', '+13:00'),
(290, 4, 'Pacific/Wake', '+12:00'),
(291, 4, 'Pacific/Wallis', '+12:00');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `data_types_identification`
--

CREATE TABLE `data_types_identification` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each type of identification.',
  `id_country` int NOT NULL COMMENT 'ID of the country to which the identification document belongs.',
  `abbreviation` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Abbreviation of the identification document.',
  `name` int NOT NULL COMMENT 'Official name of the identification document.',
  `mask` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Mask of the format in which the identification document is usually displayed, without needing to modify the value.',
  `min` tinyint NOT NULL DEFAULT '5' COMMENT 'Minimum expected size of the identification document.',
  `max` tinyint NOT NULL DEFAULT '20' COMMENT 'Maximum expected size of the identification document.',
  `person_type` enum('natural','legal') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Indicates whether the identification type is for individuals or companies.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the types of documents of the countries.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_categories`
--

CREATE TABLE `doc_categories` (
  `id` int NOT NULL COMMENT 'Unique identifier of each type of document.',
  `name` json NOT NULL COMMENT 'Type name in various languages.',
  `description` json DEFAULT NULL COMMENT 'Type description in multiple languages.',
  `prefix` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Prefix with which the document will be displayed.',
  `folder_path` blob NOT NULL COMMENT 'Path of folders and subfolders where documents of this type are stored.',
  `security_level` enum('public','low','medium','high','critical') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'All documents belonging to a type are created with the default security level corresponding to that type.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Types of documents.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_documents`
--

CREATE TABLE `doc_documents` (
  `id` int NOT NULL COMMENT 'Unique identifier for each document.',
  `id_category` int NOT NULL COMMENT 'ID of the category to which the document belongs.',
  `name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Formatted name of the document.',
  `type` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Extension or type of document.',
  `security_level` enum('public','low','medium','high','critical') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'public' COMMENT 'Security level of the document. From open to the public, so that anyone can view or download it; to critical, which refers to corporate secrets.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Document storage.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_documents_access`
--

CREATE TABLE `doc_documents_access` (
  `id` int NOT NULL COMMENT 'Unique identifier for each access to the document.',
  `id_account` int NOT NULL COMMENT 'ID of the account that accessed the document.',
  `id_document` int NOT NULL COMMENT 'ID of the document that was accessed.',
  `type` enum('preview','download') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Indicates what type of access the user had to the document.',
  `justification` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Justification of why you want to access the document.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Record of access to documents with high or higher security.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_metadata`
--

CREATE TABLE `doc_metadata` (
  `id` int NOT NULL COMMENT 'Unique identifier for each metadata.',
  `id_document` int NOT NULL COMMENT 'ID of the document to which the metadata belongs.',
  `name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unformatted name of the document.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Description of the document so that it is clear what is expected to be seen in the content.',
  `keywords` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Keywords separated by semicolon (;).',
  `other_metadata` json DEFAULT NULL COMMENT 'Other document metadata.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Document metadata for advanced searching.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_permissions`
--

CREATE TABLE `doc_permissions` (
  `id` int NOT NULL COMMENT 'Unique identifier for each permit.',
  `id_document` int NOT NULL COMMENT 'ID of the document to which special permissions are granted.',
  `id_supervisor` int NOT NULL COMMENT 'ID of the employee who oversees access to the documents.',
  `id_account` int DEFAULT NULL COMMENT 'ID of the account that is granted special permission.',
  `id_role` int DEFAULT NULL COMMENT 'ID of the role that is granted special permissions.',
  `status` enum('pending','approved','rejected') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Permit status. It starts pending and can be approved or rejected.',
  `solicitude` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Request for an account to access the document.',
  `reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Explanation of why the request for access to the document was approved or rejected. This field is not required.',
  `can_view` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether the account or role can view the document.',
  `can_download` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the account or role can download the document.',
  `can_update_data` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the account or role can update document data.',
  `can_update_content` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the account or role can update the contents of the document.',
  `deadline` timestamp NULL DEFAULT NULL COMMENT 'Deadline date and time for document permission.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Document access permissions.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_supervisors`
--

CREATE TABLE `doc_supervisors` (
  `id` int NOT NULL COMMENT 'Unique identifier for each controller.',
  `id_employee` int NOT NULL COMMENT 'Supervisor employee ID.',
  `id_category` int DEFAULT NULL COMMENT 'Category ID in which the employee will be a supervisor. Employees assigned a category will be considered as the main category.',
  `id_document` int DEFAULT NULL COMMENT 'Document ID for which the employee will be the supervisor. Employees who have a document assigned will be considered collaborators and may only act on behalf of that specific document.',
  `principal` tinyint(1) NOT NULL COMMENT 'Indicates whether the supervisor is the principal or not.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Those responsible for supervising documents.';

--
-- Disparadores `doc_supervisors`
--
DELIMITER $$
CREATE TRIGGER `set_principal_after_insert` AFTER INSERT ON `doc_supervisors` FOR EACH ROW BEGIN
  IF NEW.id_category IS NOT NULL THEN
    UPDATE doc_supervisors
    SET principal = 1
    WHERE id = NEW.id;
  ELSE
    UPDATE doc_supervisors
    SET principal = 0
    WHERE id = NEW.id;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `set_principal_after_update` AFTER UPDATE ON `doc_supervisors` FOR EACH ROW BEGIN
  IF NEW.id_category IS NOT NULL THEN
    UPDATE doc_supervisors
    SET principal = 1
    WHERE id = NEW.id;
  ELSE
    UPDATE doc_supervisors
    SET principal = 0
    WHERE id = NEW.id;
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_versions`
--

CREATE TABLE `doc_versions` (
  `id` int NOT NULL COMMENT 'Unique identifier for each version of the document.',
  `id_document` int NOT NULL COMMENT 'ID of the document to which the version belongs.',
  `id_creator` int NOT NULL COMMENT 'ID of the employee who created the version.',
  `url` blob NOT NULL COMMENT 'Encrypted URL of the document for viewing.',
  `size` bigint NOT NULL COMMENT 'Document size in bytes.',
  `version` tinyint NOT NULL DEFAULT '1' COMMENT 'Version number.',
  `status` enum('created','in_review','requires_corrections','pending','accepted','refused') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'created' COMMENT 'Indicates the status of the version: whether it was created, whether it is under review, whether it requires corrections, whether it is pending another review, whether it was approved or rejected.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Document versions.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `doc_versions_socializations`
--

CREATE TABLE `doc_versions_socializations` (
  `id` int NOT NULL COMMENT 'Unique identifier for each message.',
  `id_version` int NOT NULL COMMENT 'ID of the version by which the socialization is generated.',
  `id_account` int DEFAULT NULL COMMENT 'ID of the account that provides feedback about the version.',
  `id_supervisor` int DEFAULT NULL COMMENT 'ID of the employee supervising the document.',
  `id_socialization` int DEFAULT NULL COMMENT 'ID of the socialization to which a direct response is given.',
  `message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'User message.',
  `type` enum('correction','doubt','clarification','congratulations','report','complaint') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Type or intention of the message.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Socialization of document versions.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `fin_budgets`
--

CREATE TABLE `fin_budgets` (
  `id` int NOT NULL COMMENT 'Unique budget identifier.',
  `id_project` int DEFAULT NULL COMMENT 'ID of the project to which the budget belongs.',
  `period` varchar(50) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Budget period (e.g., 2024-Q1).',
  `amount` decimal(18,2) NOT NULL COMMENT 'Amount allocated to the budget.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Budgets for accounting accounts, departments or projects.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `fin_cashboxes`
--

CREATE TABLE `fin_cashboxes` (
  `id` int NOT NULL COMMENT 'Unique identifier of the petty cash register.',
  `id_contract` int DEFAULT NULL COMMENT 'Contract ID of the person responsible for petty cash.',
  `id_project` int DEFAULT NULL COMMENT 'ID of the project to which the petty cash was assigned.',
  `name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the box (e.g., Master box, Office box).',
  `balance` decimal(18,2) NOT NULL COMMENT 'Current petty cash balance.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Records general information about petty cash.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `fin_invoices`
--

CREATE TABLE `fin_invoices` (
  `id` int NOT NULL COMMENT 'Unique identifier for invoice.',
  `id_item` int NOT NULL COMMENT 'ID of the item being sold.',
  `id_account` int DEFAULT NULL COMMENT 'Account ID. This is used if an employee, customer, or vendor purchases something from the company.',
  `code` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique code for each invoice.',
  `sub_total` decimal(20,2) NOT NULL COMMENT 'Total price of items before taxes, discounts and withholdings.',
  `taxes` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT 'Price of taxes payable.',
  `total` decimal(22,2) NOT NULL COMMENT 'Total invoice price, after deducting discounts and adding taxes.',
  `currency` varchar(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'USD' COMMENT 'Currency in which payment was made.',
  `status` enum('pending','processes','cancelled','overdue','paid') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending' COMMENT 'Invoice status.',
  `recurrent` tinyint(1) NOT NULL COMMENT 'Indicates whether the invoice is recurring. Used for membership and/or subscription payments.',
  `due_date` date NOT NULL COMMENT 'Indicates the date on which the invoice is due.',
  `date_tolerance` date DEFAULT NULL COMMENT 'Indicates the date on which there may be a certain tolerance for payment of the invoice.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `fin_invoices_details`
--

CREATE TABLE `fin_invoices_details` (
  `id` int NOT NULL COMMENT 'Unique identifier for each invoice detail.',
  `id_invoice` int NOT NULL COMMENT 'Invoice ID to which the items are associated.',
  `id_item` int NOT NULL COMMENT 'ID of the item to be sold.',
  `quantity` int NOT NULL COMMENT 'Quantity of items purchased.',
  `taxes` decimal(10,2) NOT NULL COMMENT 'Price of the taxes that are added.',
  `total` int NOT NULL COMMENT 'Total price of each item, multiplied by the quantity purchased.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Purchase details on each invoice.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `fin_ledger_accounts`
--

CREATE TABLE `fin_ledger_accounts` (
  `id` int NOT NULL COMMENT 'Unique identifier of the accounting account.',
  `id_company` int DEFAULT NULL COMMENT 'ID of the company to which the accounting account belongs.',
  `id_parent` int DEFAULT NULL COMMENT 'Parent ledger account ID.',
  `code` varchar(50) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique accounting code (e.g., "1010" for Cash).',
  `name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Account name (e.g., Cash, Bank, Sales).',
  `type` enum('assets','liabilities','equity','income','expenses') COLLATE utf8mb4_general_ci NOT NULL,
  `initial_balance` decimal(18,2) NOT NULL COMMENT 'Initial account balance when starting the system.',
  `current_balance` decimal(18,2) NOT NULL COMMENT 'Current account balance (calculated from transactions).',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Records and organizes all financial transactions.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `fin_transactions`
--

CREATE TABLE `fin_transactions` (
  `id` int NOT NULL COMMENT 'Unique identifier of the transaction.',
  `id_account` int NOT NULL COMMENT 'ID of the account associated with the transaction.',
  `id_ledger_account` int NOT NULL COMMENT 'ID of the affected accounting account.',
  `description` varchar(255) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Brief description of the transaction.',
  `amount` decimal(18,2) NOT NULL COMMENT 'Transaction amount.',
  `type` enum('income','expense','adjustment') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Transaction type.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Record of financial transactions.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_cities`
--

CREATE TABLE `geo_cities` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each city.',
  `id_sub_division` int NOT NULL COMMENT 'ID of the subdivision to which the city belongs.',
  `id_timezone` int NOT NULL COMMENT 'ID of the time zone governing the city. This setup allows for different time zones within a country or even a subdivision.',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Original name of the city.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores cities.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_continents`
--

CREATE TABLE `geo_continents` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each continent.',
  `name` json NOT NULL COMMENT 'Continent name, written in different languages for internationalization.',
  `abbreviation` varchar(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Continent abbreviation.',
  `surface_area` int NOT NULL COMMENT 'Approximate surface area of the continent (measured in km²).'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the continents.';

--
-- Volcado de datos para la tabla `geo_continents`
--

INSERT INTO `geo_continents` (`id`, `name`, `abbreviation`, `surface_area`) VALUES
(1, '{\"ar\": \"أفريقيا\", \"bg\": \"Африка\", \"bn\": \"আফ্রিকা\", \"ca\": \"Àfrica\", \"cs\": \"Afrika\", \"da\": \"Afrika\", \"de\": \"Afrika\", \"el\": \"Αφρική\", \"en\": \"Africa\", \"eo\": \"Afriko\", \"es\": \"África\", \"et\": \"Aafrika\", \"eu\": \"Afrika\", \"fa\": \"آفریقا\", \"fi\": \"Afrikka\", \"fr\": \"Afrique\", \"gn\": \"Áfrika\", \"he\": \"אפריקה\", \"hi\": \"अफ़्रीका\", \"hr\": \"Afrika\", \"hu\": \"Afrika\", \"id\": \"Afrika\", \"is\": \"Afríka\", \"it\": \"Africa\", \"ja\": \"アフリカ\", \"kk\": \"Африка\", \"km\": \"អាហ្វ្រិក\", \"lt\": \"Afrika\", \"lu\": \"Afrika\", \"lv\": \"Āfrika\", \"mk\": \"Африка\", \"ml\": \"ആഫ്രിക്ക\", \"mm\": \"အာဖရိက\", \"ms\": \"Afrika\", \"my\": \"အာဖရိက\", \"nl\": \"Afrika\", \"pl\": \"Afryka\", \"pt\": \"África\", \"ro\": \"Africa\", \"ru\": \"Африка\", \"sk\": \"Afrika\", \"sl\": \"Afrika\", \"sm\": \"Aferika\", \"sr\": \"Afrika\", \"sv\": \"Afrika\", \"ta\": \"ஆப்ரிக்கா\", \"th\": \"แอฟริกา\", \"tl\": \"Aprika\", \"tr\": \"Afrika\", \"ug\": \"ئافرىقا\", \"uk\": \"Африка\", \"vi\": \"Châu Phi\", \"ar-TN\": \"أفريقيا\", \"de-CH\": \"Afrika\", \"de-DE\": \"Afrika\", \"en-GB\": \"Africa\", \"en-US\": \"Africa\", \"fa-IR\": \"آفریقا\", \"ko-KR\": \"아프리카\", \"ms-MY\": \"Afrika\", \"nb-NO\": \"Afrika\", \"pt-BR\": \"África\", \"zh-CN\": \"非洲\", \"zh-TW\": \"非洲\", \"sr-CYR\": \"Африка\", \"az-Latn\": \"Afrika\", \"kur-CKB\": \"ئه‌فریقا\", \"uz-Cyrl\": \"Африка\", \"uz-Latn\": \"Afrika\"}', 'AFR', 30370000),
(2, '{\"ar\": \"أمريكا\", \"bg\": \"Америка\", \"bn\": \"আমেরিকা\", \"ca\": \"Amèrica\", \"cs\": \"Amerika\", \"da\": \"Amerika\", \"de\": \"Amerika\", \"el\": \"Αμερική\", \"en\": \"America\", \"eo\": \"Ameriko\", \"es\": \"América\", \"et\": \"Ameerika\", \"eu\": \"Amerika\", \"fa\": \"آمریکا\", \"fi\": \"Amerikka\", \"fr\": \"Amérique\", \"gn\": \"Amérika\", \"he\": \"אמריקה\", \"hi\": \"अमेरिका\", \"hr\": \"Amerika\", \"hu\": \"Amerika\", \"id\": \"Amerika\", \"is\": \"Ameríka\", \"it\": \"America\", \"ja\": \"アメリカ\", \"kk\": \"Америка\", \"km\": \"អាមេរិក\", \"lt\": \"Amerika\", \"lu\": \"Amerika\", \"lv\": \"Amerika\", \"mk\": \"Америка\", \"ml\": \"അമേരിക്ക\", \"mm\": \"အမေရိက\", \"ms\": \"Amerika\", \"my\": \"အမေရိက\", \"nl\": \"Amerika\", \"pl\": \"Ameryka\", \"pt\": \"América\", \"ro\": \"America\", \"ru\": \"Америка\", \"sk\": \"Amerika\", \"sl\": \"Amerika\", \"sm\": \"Amerika\", \"sr\": \"Amerika\", \"sv\": \"Amerika\", \"ta\": \"அமெரிக்கா\", \"th\": \"อเมริกา\", \"tl\": \"Amerika\", \"tr\": \"Amerika\", \"ug\": \"ئامېرىكا\", \"uk\": \"Америка\", \"vi\": \"Châu Mỹ\", \"ar-TN\": \"أمريكا\", \"de-CH\": \"Amerika\", \"de-DE\": \"Amerika\", \"en-GB\": \"America\", \"en-US\": \"America\", \"fa-IR\": \"آمریکا\", \"ko-KR\": \"아메리카\", \"ms-MY\": \"Amerika\", \"nb-NO\": \"Amerika\", \"pt-BR\": \"América\", \"zh-CN\": \"美洲\", \"zh-TW\": \"美洲\", \"sr-CYR\": \"Америка\", \"az-Latn\": \"Amerika\", \"kur-CKB\": \"ئه‌مریكا\", \"uz-Cyrl\": \"Америка\", \"uz-Latn\": \"Amerika\"}', 'AME', 43072780),
(3, '{\"ar\": \"أنتاركتيكا\", \"bg\": \"Антарктида\", \"bn\": \"অ্যান্টার্কটিকা\", \"ca\": \"Antàrtida\", \"cs\": \"Antarktida\", \"da\": \"Antarktis\", \"de\": \"Antarktis\", \"el\": \"Ανταρκτική\", \"en\": \"Antarctica\", \"eo\": \"Antarkto\", \"es\": \"Antártida\", \"et\": \"Antarktika\", \"eu\": \"Antartika\", \"fa\": \"جنوبگان\", \"fi\": \"Antarktis\", \"fr\": \"Antarctique\", \"gn\": \"Antártida\", \"he\": \"אנטארקטיקה\", \"hi\": \"अंटार्कटिका\", \"hr\": \"Antarktika\", \"hu\": \"Antarktisz\", \"id\": \"Antarktika\", \"is\": \"Suðurskautslandið\", \"it\": \"Antartide\", \"ja\": \"南極\", \"kk\": \"Антарктида\", \"km\": \"អង់តាក់ទិក\", \"lt\": \"Antarktida\", \"lu\": \"Antarktika\", \"lv\": \"Antarktīda\", \"mk\": \"Антарктик\", \"ml\": \"അന്റാർട്ടിക്ക\", \"mm\": \"အန်တာတိက\", \"ms\": \"Antartika\", \"my\": \"အန်တာတိက\", \"nl\": \"Antarctica\", \"pl\": \"Antarktyda\", \"pt\": \"Antártida\", \"ro\": \"Antarctica\", \"ru\": \"Антарктида\", \"sk\": \"Antarktída\", \"sl\": \"Antarktika\", \"sm\": \"Atika\", \"sr\": \"Antarktik\", \"sv\": \"Antarktis\", \"ta\": \"அண்டார்டிகா\", \"th\": \"ทวีปแอนตาร์กติกา\", \"tl\": \"Antartiko\", \"tr\": \"Antarktika\", \"ug\": \"ئانتاركتىكا\", \"uk\": \"Антарктида\", \"vi\": \"Nam Cực\", \"ar-TN\": \"أنتاركتيكا\", \"de-CH\": \"Antarktis\", \"de-DE\": \"Antarktis\", \"en-GB\": \"Antarctica\", \"en-US\": \"Antarctica\", \"fa-IR\": \"جنوبگان\", \"ko-KR\": \"남극 대륙\", \"ms-MY\": \"Antartika\", \"nb-NO\": \"Antarktis\", \"pt-BR\": \"Antártida\", \"zh-CN\": \"南极洲\", \"zh-TW\": \"南極洲\", \"sr-CYR\": \"Антарктик\", \"az-Latn\": \"Antarktida\", \"kur-CKB\": \"ئانتارکتیکا\", \"uz-Cyrl\": \"Антарктика\", \"uz-Latn\": \"Antarktika\"}', 'ANT', 14000000),
(4, '{\"ar\": \"آسيا\", \"bg\": \"Азия\", \"bn\": \"এশিয়া\", \"ca\": \"Àsia\", \"cs\": \"Asie\", \"da\": \"Asien\", \"de\": \"Asien\", \"el\": \"Ασία\", \"en\": \"Asia\", \"eo\": \"Azio\", \"es\": \"Asia\", \"et\": \"Aasia\", \"eu\": \"Asia\", \"fa\": \"آسیا\", \"fi\": \"Aasia\", \"fr\": \"Asie\", \"gn\": \"Asia\", \"he\": \"אסיה\", \"hi\": \"एशिया\", \"hr\": \"Azija\", \"hu\": \"Ázsia\", \"id\": \"Asia\", \"is\": \"Asía\", \"it\": \"Asia\", \"ja\": \"アジア\", \"kk\": \"Азия\", \"km\": \"អាស៊ី\", \"lt\": \"Azija\", \"lu\": \"Asia\", \"lv\": \"Āzija\", \"mk\": \"Азија\", \"ml\": \"ആഷ്യ\", \"mm\": \"အာရှ\", \"ms\": \"Asia\", \"my\": \"အာရှ\", \"nl\": \"Azië\", \"pl\": \"Azja\", \"pt\": \"Ásia\", \"ro\": \"Asia\", \"ru\": \"Азия\", \"sk\": \"Ázia\", \"sl\": \"Azija\", \"sm\": \"Asia\", \"sr\": \"Azija\", \"sv\": \"Asien\", \"ta\": \"ஆசியா\", \"th\": \"เอเชีย\", \"tl\": \"Asya\", \"tr\": \"Asya\", \"ug\": \"ئاسيا\", \"uk\": \"Азія\", \"vi\": \"Châu Á\", \"ar-TN\": \"آسيا\", \"de-CH\": \"Asien\", \"de-DE\": \"Asien\", \"en-GB\": \"Asia\", \"en-US\": \"Asia\", \"fa-IR\": \"آسیا\", \"ko-KR\": \"아시아\", \"ms-MY\": \"Asia\", \"nb-NO\": \"Asia\", \"pt-BR\": \"Ásia\", \"zh-CN\": \"亚洲\", \"zh-TW\": \"亞洲\", \"sr-CYR\": \"Азија\", \"az-Latn\": \"Asiya\", \"kur-CKB\": \"ئاسیا\", \"uz-Cyrl\": \"Осиё\", \"uz-Latn\": \"Osiyo\"}', 'ASI', 44580000),
(5, '{\"ar\": \"أوروبا\", \"bg\": \"Европа\", \"bn\": \"ইউরোপ\", \"ca\": \"Europa\", \"cs\": \"Evropa\", \"da\": \"Europa\", \"de\": \"Europa\", \"el\": \"Ευρώπη\", \"en\": \"Europe\", \"eo\": \"Eŭropo\", \"es\": \"Europa\", \"et\": \"Euroopa\", \"eu\": \"Europa\", \"fa\": \"اروپا\", \"fi\": \"Eurooppa\", \"fr\": \"Europe\", \"gn\": \"Európa\", \"he\": \"אירופה\", \"hi\": \"यूरोप\", \"hr\": \"Europa\", \"hu\": \"Európa\", \"id\": \"Eropa\", \"is\": \"Evrópa\", \"it\": \"Europa\", \"ja\": \"ヨーロッパ\", \"kk\": \"Еуропа\", \"km\": \"អឺរ៉ុប\", \"lt\": \"Europa\", \"lu\": \"Europa\", \"lv\": \"Eiropa\", \"mk\": \"Европа\", \"ml\": \"യൂറോപ്പ്\", \"mm\": \"ဥရောပ\", \"ms\": \"Eropah\", \"my\": \"ဥရောပ\", \"nl\": \"Europa\", \"pl\": \"Europa\", \"pt\": \"Europa\", \"ro\": \"Europa\", \"ru\": \"Европа\", \"sk\": \"Európa\", \"sl\": \"Evropa\", \"sm\": \"Europa\", \"sr\": \"Evropa\", \"sv\": \"Europa\", \"ta\": \"ஐரோப்பா\", \"th\": \"ยุโรป\", \"tl\": \"Europa\", \"tr\": \"Avrupa\", \"ug\": \"ياۋروپا\", \"uk\": \"Європа\", \"vi\": \"Châu Âu\", \"ar-TN\": \"أوروبا\", \"de-CH\": \"Europa\", \"de-DE\": \"Europa\", \"en-GB\": \"Europe\", \"en-US\": \"Europe\", \"fa-IR\": \"اروپا\", \"ko-KR\": \"유럽\", \"ms-MY\": \"Eropah\", \"nb-NO\": \"Europa\", \"pt-BR\": \"Europa\", \"zh-CN\": \"欧洲\", \"zh-TW\": \"歐洲\", \"sr-CYR\": \"Европа\", \"az-Latn\": \"Avropa\", \"kur-CKB\": \"ئه‌ورووپا\", \"uz-Cyrl\": \"Европа\", \"uz-Latn\": \"Yevropa\"}', 'EUR', 10180000),
(6, '{\"ar\": \"أوقيانوسيا\", \"bg\": \"Океания\", \"bn\": \"ওশিয়ানিয়া\", \"ca\": \"Oceania\", \"cs\": \"Oceánie\", \"da\": \"Oceanien\", \"de\": \"Ozeanien\", \"el\": \"Ωκεανία\", \"en\": \"Oceania\", \"eo\": \"Oceanio\", \"es\": \"Oceanía\", \"et\": \"Okeaania\", \"eu\": \"Ozeania\", \"fa\": \"اقیانوسیه\", \"fi\": \"Oseania\", \"fr\": \"Océanie\", \"gn\": \"Oceania\", \"he\": \"אוקיאניה\", \"hi\": \"ओशिनिया\", \"hr\": \"Oceanija\", \"hu\": \"Óceánia\", \"id\": \"Oseania\", \"is\": \"Eyjaálfa\", \"it\": \"Oceania\", \"ja\": \"オセアニア\", \"kk\": \"Океания\", \"km\": \"អូស្សេនី\", \"lt\": \"Okeanija\", \"lu\": \"Oceania\", \"lv\": \"Okeānija\", \"mk\": \"Океанија\", \"ml\": \"ഓഷ്യനിയ\", \"mm\": \"အိုက်စနီးရှား\", \"ms\": \"Oceania\", \"my\": \"ဥက္ကဌာန္း\", \"nl\": \"Oceanië\", \"pl\": \"Oceania\", \"pt\": \"Oceania\", \"ro\": \"Oceania\", \"ru\": \"Океания\", \"sk\": \"Oceánia\", \"sl\": \"Oceanija\", \"sm\": \"Oceania\", \"sr\": \"Okeanija\", \"sv\": \"Oceanien\", \"ta\": \"ஓஷியானியா\", \"th\": \"โอเชียเนีย\", \"tl\": \"Oceania\", \"tr\": \"Okyanusya\", \"ug\": \"ئوكيانىيە\", \"uk\": \"Океанія\", \"vi\": \"Châu Đại Dương\", \"ar-TN\": \"أوقيانوسيا\", \"de-CH\": \"Ozeanien\", \"de-DE\": \"Ozeanien\", \"en-GB\": \"Oceania\", \"en-US\": \"Oceania\", \"fa-IR\": \"اقیانوسیه\", \"ko-KR\": \"오세아니아\", \"ms-MY\": \"Oceania\", \"nb-NO\": \"Oseania\", \"pt-BR\": \"Oceania\", \"zh-CN\": \"大洋洲\", \"zh-TW\": \"大洋洲\", \"sr-CYR\": \"Океанија\", \"az-Latn\": \"Okeaniya\", \"kur-CKB\": \"ئۆقیانووسیا\", \"uz-Cyrl\": \"Океания\", \"uz-Latn\": \"Okeaniya\"}', 'OCE', 8530000);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_countries`
--

CREATE TABLE `geo_countries` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each country.',
  `id_region` int NOT NULL COMMENT 'ID of the region to which the country belongs.',
  `id_capital` int DEFAULT NULL COMMENT 'ID of the country''s capital city.',
  `id_flag` int NOT NULL COMMENT 'ID of the country’s flag.',
  `popular_name` json NOT NULL COMMENT 'Name of the country, written in different languages for internationalization.',
  `official_name` json NOT NULL COMMENT 'Official language of the country translated into several languages.',
  `abbreviation` json NOT NULL COMMENT 'ISO 3166-1 alpha-2 two-letter country codes and ISO 3166-1 alpha-3 three-letter country codes of the country.',
  `surface_area` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Approximate surface area of the country (measured in km²).',
  `tld` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Internet top level domains'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the countries.';

--
-- Volcado de datos para la tabla `geo_countries`
--

INSERT INTO `geo_countries` (`id`, `id_region`, `id_capital`, `id_flag`, `popular_name`, `official_name`, `abbreviation`, `surface_area`, `tld`) VALUES
(1, 15, NULL, 1, '{\"en\": \"Afghanistan\", \"es\": \"Afganistán\"}', '{\"en\": \"Islamic Republic of Afghanistan\", \"es\": \"República Islámica de Afganistán\"}', '{\"two\": \"af\", \"three\": \"AFG\"}', '652,230 km²', '.af'),
(2, 19, NULL, 2, '{\"en\": \"Albania\", \"es\": \"Albania\"}', '{\"en\": \"Republic of Albania\", \"es\": \"República de Albania\"}', '{\"two\": \"al\", \"three\": \"ALB\"}', '28,748 km²', '.al'),
(3, 3, NULL, 3, '{\"en\": \"Algeria\", \"es\": \"Argelia\"}', '{\"en\": \"People\'s Democratic Republic of Algeria\", \"es\": \"República Democrática y Popular de Argelia\"}', '{\"two\": \"dz\", \"three\": \"DZA\"}', '2,381,741 km²', '.dz'),
(4, 7, NULL, 4, '{\"en\": \"American Samoa\", \"es\": \"Samoa Americana\"}', '{\"en\": \"American Samoa\", \"es\": \"Samoa Americana\"}', '{\"two\": \"as\", \"three\": \"ASM\"}', '199 km²', '.as'),
(5, 17, NULL, 5, '{\"en\": \"Andorra\", \"es\": \"Andorra\"}', '{\"en\": \"Principality of Andorra\", \"es\": \"Principado de Andorra\"}', '{\"two\": \"ad\", \"three\": \"AND\"}', '468 km²', '.ad'),
(6, 5, NULL, 6, '{\"en\": \"Angola\", \"es\": \"Angola\"}', '{\"en\": \"Republic of Angola\", \"es\": \"República de Angola\"}', '{\"two\": \"ao\", \"three\": \"AGO\"}', '1,246,700 km²', '.ao'),
(7, 7, NULL, 7, '{\"en\": \"Anguilla\", \"es\": \"Anguila\"}', '{\"en\": \"Anguilla\", \"es\": \"Anguila\"}', '{\"two\": \"ai\", \"three\": \"AIA\"}', '91 km²', '.ai'),
(8, 10, NULL, 8, '{\"en\": \"Antarctica\", \"es\": \"Antártida\"}', '{\"en\": \"Antarctica\", \"es\": \"Antártida\"}', '{\"two\": \"aq\", \"three\": \"ATA\"}', '14,000,000 km²', '.aq'),
(9, 7, NULL, 9, '{\"en\": \"Antigua and Barbuda\", \"es\": \"Antigua y Barbuda\"}', '{\"en\": \"Antigua and Barbuda\", \"es\": \"Antigua y Barbuda\"}', '{\"two\": \"ag\", \"three\": \"ATG\"}', '442 km²', '.ag'),
(10, 6, NULL, 10, '{\"en\": \"Argentina\", \"es\": \"Argentina\"}', '{\"en\": \"Argentine Republic\", \"es\": \"República Argentina\"}', '{\"two\": \"ar\", \"three\": \"ARG\"}', '2,780,400 km²', '.ar'),
(11, 15, NULL, 11, '{\"en\": \"Armenia\", \"es\": \"Armenia\"}', '{\"en\": \"Republic of Armenia\", \"es\": \"República de Armenia\"}', '{\"two\": \"am\", \"three\": \"ARM\"}', '29,743 km²', '.am'),
(12, 7, NULL, 12, '{\"en\": \"Aruba\", \"es\": \"Aruba\"}', '{\"en\": \"Aruba\", \"es\": \"Aruba\"}', '{\"two\": \"aw\", \"three\": \"ABW\"}', '180 km²', '.aw'),
(13, 3, NULL, 13, '{\"en\": \"Ascension Island\", \"es\": \"Isla Ascensión\"}', '{\"en\": \"Ascension Island\", \"es\": \"Isla Ascensión\"}', '{\"two\": \"sh-ac\", \"three\": \"ASC\"}', '88 km²', '.ac'),
(14, 25, NULL, 14, '{\"en\": \"Australia\", \"es\": \"Australia\"}', '{\"en\": \"Commonwealth of Australia\", \"es\": \"Commonwealth de Australia\"}', '{\"two\": \"au\", \"three\": \"AUS\"}', '7,692,024 km²', '.au'),
(15, 20, NULL, 15, '{\"en\": \"Austria\", \"es\": \"Austria\"}', '{\"en\": \"Republic of Austria\", \"es\": \"República de Austria\"}', '{\"two\": \"at\", \"three\": \"AUT\"}', '83,879 km²', '.at'),
(16, 12, NULL, 16, '{\"en\": \"Azerbaijan\", \"es\": \"Azerbaiyán\"}', '{\"en\": \"Republic of Azerbaijan\", \"es\": \"República de Azerbaiyán\"}', '{\"two\": \"az\", \"three\": \"AZE\"}', '86,600 km²', '.az'),
(17, 7, NULL, 17, '{\"en\": \"Bahamas\", \"es\": \"Bahamas\"}', '{\"en\": \"Commonwealth of the Bahamas\", \"es\": \"Commonwealth de las Bahamas\"}', '{\"two\": \"bs\", \"three\": \"BHS\"}', '13,880 km²', '.bs'),
(18, 12, NULL, 18, '{\"en\": \"Bahrain\", \"es\": \"Baréin\"}', '{\"en\": \"Kingdom of Bahrain\", \"es\": \"Reino de Baréin\"}', '{\"two\": \"bh\", \"three\": \"BHR\"}', '765 km²', '.bh'),
(19, 13, NULL, 19, '{\"en\": \"Bangladesh\", \"es\": \"Bangladés\"}', '{\"en\": \"People\'s Republic of Bangladesh\", \"es\": \"República Popular de Bangladesh\"}', '{\"two\": \"bd\", \"three\": \"BGD\"}', '147,570 km²', '.bd'),
(20, 7, NULL, 20, '{\"en\": \"Barbados\", \"es\": \"Barbados\"}', '{\"en\": \"Barbados\", \"es\": \"Barbados\"}', '{\"two\": \"bb\", \"three\": \"BRB\"}', '430 km²', '.bb'),
(21, 16, NULL, 21, '{\"en\": \"Belarus\", \"es\": \"Bielorrusia\"}', '{\"en\": \"Republic of Belarus\", \"es\": \"República de Bielorrusia\"}', '{\"two\": \"by\", \"three\": \"BLR\"}', '207,600 km²', '.by'),
(22, 18, NULL, 22, '{\"en\": \"Belgium\", \"es\": \"Bélgica\"}', '{\"en\": \"Kingdom of Belgium\", \"es\": \"Reino de Bélgica\"}', '{\"two\": \"be\", \"three\": \"BEL\"}', '30,528 km²', '.be'),
(23, 9, NULL, 23, '{\"en\": \"Belize\", \"es\": \"Belice\"}', '{\"en\": \"Belize\", \"es\": \"Belice\"}', '{\"two\": \"bz\", \"three\": \"BLZ\"}', '22,966 km²', '.bz'),
(24, 4, NULL, 24, '{\"en\": \"Benin\", \"es\": \"Benín\"}', '{\"en\": \"Republic of Benin\", \"es\": \"República de Benín\"}', '{\"two\": \"bj\", \"three\": \"BEN\"}', '112,622 km²', '.bj'),
(25, 7, NULL, 25, '{\"en\": \"Bermuda\", \"es\": \"Bermudas\"}', '{\"en\": \"Bermuda\", \"es\": \"Bermudas\"}', '{\"two\": \"bm\", \"three\": \"BMU\"}', '53.3 km²', '.bm'),
(26, 13, NULL, 26, '{\"en\": \"Bhutan\", \"es\": \"Bután\"}', '{\"en\": \"Kingdom of Bhutan\", \"es\": \"Reino de Bután\"}', '{\"two\": \"bt\", \"three\": \"BTN\"}', '38,394 km²', '.bt'),
(27, 6, NULL, 27, '{\"en\": \"Bolivia\", \"es\": \"Bolivia\"}', '{\"en\": \"Plurinational State of Bolivia\", \"es\": \"Estado Plurinacional de Bolivia\"}', '{\"two\": \"bo\", \"three\": \"BOL\"}', '1,098,581 km²', '.bo'),
(28, 7, NULL, 28, '{\"en\": \"Bonaire, Sint Eustatius and Saba\", \"es\": \"Bonaire, Sint Eustatius y Saba\"}', '{\"en\": \"Special Municipality of the Netherlands\", \"es\": \"Municipio especial de los Países Bajos\"}', '{\"two\": \"bq\", \"three\": \"BES\"}', '328 km²', '.bq'),
(29, 19, NULL, 29, '{\"en\": \"Bosnia and Herzegovina\", \"es\": \"Bosnia y Herzegovina\"}', '{\"en\": \"Bosnia and Herzegovina\", \"es\": \"Bosnia y Herzegovina\"}', '{\"two\": \"ba\", \"three\": \"BIH\"}', '51,197 km²', '.ba'),
(30, 5, NULL, 30, '{\"en\": \"Botswana\", \"es\": \"Botsuana\"}', '{\"en\": \"Republic of Botswana\", \"es\": \"República de Botsuana\"}', '{\"two\": \"bw\", \"three\": \"BWA\"}', '581,730 km²', '.bw'),
(31, 6, NULL, 31, '{\"en\": \"Brazil\", \"es\": \"Brasil\"}', '{\"en\": \"Federative Republic of Brazil\", \"es\": \"República Federativa de Brasil\"}', '{\"two\": \"br\", \"three\": \"BRA\"}', '8,515,767 km²', '.br'),
(32, 7, NULL, 32, '{\"en\": \"British Indian Ocean Territory\", \"es\": \"Territorio Británico del Océano Índico\"}', '{\"en\": \"British Indian Ocean Territory\", \"es\": \"Territorio Británico del Océano Índico\"}', '{\"two\": \"io\", \"three\": \"IOT\"}', '60 km²', '.io'),
(33, 14, NULL, 33, '{\"en\": \"Brunei Darussalam\", \"es\": \"Brunéi\"}', '{\"en\": \"Nation of Brunei, Abode of Peace\", \"es\": \"Nación de Brunéi, Morada de la Paz\"}', '{\"two\": \"bn\", \"three\": \"BRN\"}', '5,765 km²', '.bn'),
(34, 20, NULL, 34, '{\"en\": \"Bulgaria\", \"es\": \"Bulgaria\"}', '{\"en\": \"Republic of Bulgaria\", \"es\": \"República de Bulgaria\"}', '{\"two\": \"bg\", \"three\": \"BGR\"}', '110,994 km²', '.bg'),
(35, 4, NULL, 35, '{\"en\": \"Burkina Faso\", \"es\": \"Burkina Faso\"}', '{\"en\": \"Burkina Faso\", \"es\": \"Burkina Faso\"}', '{\"two\": \"bf\", \"three\": \"BFA\"}', '272,967 km²', '.bf'),
(36, 5, NULL, 36, '{\"en\": \"Burundi\", \"es\": \"Burundi\"}', '{\"en\": \"Republic of Burundi\", \"es\": \"República de Burundi\"}', '{\"two\": \"bi\", \"three\": \"BDI\"}', '27,834 km²', '.bi'),
(37, 5, NULL, 37, '{\"en\": \"Cape Verde\", \"es\": \"Cabo Verde\"}', '{\"en\": \"Republic of Cabo Verde\", \"es\": \"República de Cabo Verde\"}', '{\"two\": \"cv\", \"three\": \"CPV\"}', '4,033 km²', '.cv'),
(38, 14, NULL, 38, '{\"en\": \"Cambodia\", \"es\": \"Camboya\"}', '{\"en\": \"Kingdom of Cambodia\", \"es\": \"Reino de Camboya\"}', '{\"two\": \"kh\", \"three\": \"KHM\"}', '181,035 km²', '.kh'),
(39, 4, NULL, 39, '{\"en\": \"Cameroon\", \"es\": \"Camerún\"}', '{\"en\": \"Republic of Cameroon\", \"es\": \"República de Camerún\"}', '{\"two\": \"cm\", \"three\": \"CMR\"}', '475,442 km²', '.cm'),
(40, 8, NULL, 40, '{\"en\": \"Canada\", \"es\": \"Canadá\"}', '{\"en\": \"Canada\", \"es\": \"Canadá\"}', '{\"two\": \"ca\", \"three\": \"CAN\"}', '9,984,670 km²', '.ca'),
(41, 7, NULL, 41, '{\"en\": \"Cayman Islands\", \"es\": \"Islas Caimán\"}', '{\"en\": \"Cayman Islands\", \"es\": \"Islas Caimán\"}', '{\"two\": \"ky\", \"three\": \"CYM\"}', '264 km²', '.ky'),
(42, 4, NULL, 42, '{\"en\": \"Central African Republic\", \"es\": \"República Centroafricana\"}', '{\"en\": \"Central African Republic\", \"es\": \"República Centroafricana\"}', '{\"two\": \"cf\", \"three\": \"CAF\"}', '622,984 km²', '.cf'),
(43, 4, NULL, 43, '{\"en\": \"Chad\", \"es\": \"Chad\"}', '{\"en\": \"Republic of Chad\", \"es\": \"República de Chad\"}', '{\"two\": \"td\", \"three\": \"TCD\"}', '1,284,000 km²', '.td'),
(44, 6, NULL, 44, '{\"en\": \"Chile\", \"es\": \"Chile\"}', '{\"en\": \"Republic of Chile\", \"es\": \"República de Chile\"}', '{\"two\": \"cl\", \"three\": \"CHL\"}', '756,102 km²', '.cl'),
(45, 11, NULL, 45, '{\"en\": \"China\", \"es\": \"China\"}', '{\"en\": \"People\'s Republic of China\", \"es\": \"República Popular China\"}', '{\"two\": \"cn\", \"three\": \"CHN\"}', '9,596,961 km²', '.cn'),
(46, 25, NULL, 46, '{\"en\": \"Christmas Island\", \"es\": \"Isla Navidad\"}', '{\"en\": \"Territory of Christmas Island\", \"es\": \"Territorio de Isla Navidad\"}', '{\"two\": \"cx\", \"three\": \"CXR\"}', '135 km²', '.cx'),
(47, 25, NULL, 47, '{\"en\": \"Cocos (Keeling) Islands\", \"es\": \"Islas Cocos (Keeling)\"}', '{\"en\": \"Territory of Cocos (Keeling) Islands\", \"es\": \"Territorio de las Islas Cocos (Keeling)\"}', '{\"two\": \"cc\", \"three\": \"CCK\"}', '14 km²', '.cc'),
(48, 9, NULL, 48, '{\"en\": \"Colombia\", \"es\": \"Colombia\"}', '{\"en\": \"Republic of Colombia\", \"es\": \"República de Colombia\"}', '{\"two\": \"co\", \"three\": \"COL\"}', '1,141,748 km²', '.co'),
(49, 5, NULL, 49, '{\"en\": \"Comoros\", \"es\": \"Comoras\"}', '{\"en\": \"Union of the Comoros\", \"es\": \"Unión de las Comoras\"}', '{\"two\": \"km\", \"three\": \"COM\"}', '2235 km²', '.km'),
(50, 22, NULL, 50, '{\"en\": \"Cook Islands\", \"es\": \"Islas Cook\"}', '{\"en\": \"Cook Islands\", \"es\": \"Islas Cook\"}', '{\"two\": \"ck\", \"three\": \"COK\"}', '236 km²', '.ck'),
(51, 9, NULL, 51, '{\"en\": \"Costa Rica\", \"es\": \"Costa Rica\"}', '{\"en\": \"Republic of Costa Rica\", \"es\": \"República de Costa Rica\"}', '{\"two\": \"cr\", \"three\": \"CRI\"}', '51,100 km²', '.cr'),
(52, 17, NULL, 52, '{\"en\": \"Croatia\", \"es\": \"Croacia\"}', '{\"en\": \"Republic of Croatia\", \"es\": \"República de Croacia\"}', '{\"two\": \"hr\", \"three\": \"HRV\"}', '56,594 km²', '.hr'),
(53, 7, NULL, 53, '{\"en\": \"Cuba\", \"es\": \"Cuba\"}', '{\"en\": \"Republic of Cuba\", \"es\": \"República de Cuba\"}', '{\"two\": \"cu\", \"three\": \"CUB\"}', '109,884 km²', '.cu'),
(54, 7, NULL, 54, '{\"en\": \"Curaçao\", \"es\": \"Curaçao\"}', '{\"en\": \"Curaçao\", \"es\": \"Curaçao\"}', '{\"two\": \"cw\", \"three\": \"CUW\"}', '444 km²', '.cw'),
(55, 12, NULL, 55, '{\"en\": \"Cyprus\", \"es\": \"Chipre\"}', '{\"en\": \"Republic of Cyprus\", \"es\": \"República de Chipre\"}', '{\"two\": \"cy\", \"three\": \"CYP\"}', '9,251 km²', '.cy'),
(56, 20, NULL, 56, '{\"en\": \"Czech Republic\", \"es\": \"República Checa\"}', '{\"en\": \"Czech Republic\", \"es\": \"República Checa\"}', '{\"two\": \"cz\", \"three\": \"CZE\"}', '78,866 km²', '.cz'),
(57, 4, NULL, 57, '{\"en\": \"Côte d\'Ivoire\", \"es\": \"Costa de Marfil\"}', '{\"en\": \"Republic of Côte d\'Ivoire\", \"es\": \"República de Côte d\'Ivoire\"}', '{\"two\": \"ci\", \"three\": \"CIV\"}', '322,463 km²', '.ci'),
(58, 2, NULL, 58, '{\"en\": \"Democratic Republic of the Congo\", \"es\": \"República Democrática del Congo\"}', '{\"en\": \"Democratic Republic of the Congo\", \"es\": \"República Democrática del Congo\"}', '{\"two\": \"cd\", \"three\": \"COD\"}', '2,344,858 km²', '.cd'),
(59, 16, NULL, 59, '{\"en\": \"Denmark\", \"es\": \"Dinamarca\"}', '{\"en\": \"Kingdom of Denmark\", \"es\": \"Reino de Dinamarca\"}', '{\"two\": \"dk\", \"three\": \"DNK\"}', '42,933 km²', '.dk'),
(60, 25, NULL, 60, '{\"en\": \"Diego Garcia\", \"es\": \"Diego García\"}', '{\"en\": \"British Indian Ocean Territory\", \"es\": \"Territorio Británico del Océano Índico\"}', '{\"two\": \"dg\", \"three\": \"IOT\"}', '27 km²', '.io'),
(61, 5, NULL, 61, '{\"en\": \"Djibouti\", \"es\": \"Yibuti\"}', '{\"en\": \"Republic of Djibouti\", \"es\": \"República de Yibuti\"}', '{\"two\": \"dj\", \"three\": \"DJI\"}', '23,200 km²', '.dj'),
(62, 7, NULL, 62, '{\"en\": \"Dominica\", \"es\": \"Dominica\"}', '{\"en\": \"Commonwealth of Dominica\", \"es\": \"Mancomunidad de Dominica\"}', '{\"two\": \"dm\", \"three\": \"DMA\"}', '751 km²', '.dm'),
(63, 9, NULL, 63, '{\"en\": \"Dominican Republic\", \"es\": \"República Dominicana\"}', '{\"en\": \"Dominican Republic\", \"es\": \"República Dominicana\"}', '{\"two\": \"do\", \"three\": \"DOM\"}', '48,671 km²', '.do'),
(64, 6, NULL, 64, '{\"en\": \"Ecuador\", \"es\": \"Ecuador\"}', '{\"en\": \"Republic of Ecuador\", \"es\": \"República del Ecuador\"}', '{\"two\": \"ec\", \"three\": \"ECU\"}', '283,561 km²', '.ec'),
(65, 3, NULL, 65, '{\"en\": \"Egypt\", \"es\": \"Egipto\"}', '{\"en\": \"Arab Republic of Egypt\", \"es\": \"República Árabe de Egipto\"}', '{\"two\": \"eg\", \"three\": \"EGY\"}', '1,001,450 km²', '.eg'),
(66, 9, NULL, 66, '{\"en\": \"El Salvador\", \"es\": \"El Salvador\"}', '{\"en\": \"Republic of El Salvador\", \"es\": \"República de El Salvador\"}', '{\"two\": \"sv\", \"three\": \"SLV\"}', '21,041 km²', '.sv'),
(67, 5, NULL, 67, '{\"en\": \"Equatorial Guinea\", \"es\": \"Guinea Ecuatorial\"}', '{\"en\": \"Republic of Equatorial Guinea\", \"es\": \"República de Guinea Ecuatorial\"}', '{\"two\": \"gq\", \"three\": \"GNQ\"}', '28,051 km²', '.gq'),
(68, 5, NULL, 68, '{\"en\": \"Eritrea\", \"es\": \"Eritrea\"}', '{\"en\": \"State of Eritrea\", \"es\": \"Estado de Eritrea\"}', '{\"two\": \"er\", \"three\": \"ERI\"}', '117,600 km²', '.er'),
(69, 16, NULL, 69, '{\"en\": \"Estonia\", \"es\": \"Estonia\"}', '{\"en\": \"Republic of Estonia\", \"es\": \"República de Estonia\"}', '{\"two\": \"ee\", \"three\": \"EST\"}', '45,227 km²', '.ee'),
(70, 5, NULL, 70, '{\"en\": \"Eswatini\", \"es\": \"Eswatini\"}', '{\"en\": \"Kingdom of Eswatini\", \"es\": \"Reino de Eswatini\"}', '{\"two\": \"sz\", \"three\": \"SWZ\"}', '17,364 km²', '.sz'),
(71, 5, NULL, 71, '{\"en\": \"Ethiopia\", \"es\": \"Etiopía\"}', '{\"en\": \"Federal Democratic Republic of Ethiopia\", \"es\": \"República Democrática Federal de Etiopía\"}', '{\"two\": \"et\", \"three\": \"ETH\"}', '1,104,300 km²', '.et'),
(72, 6, NULL, 72, '{\"en\": \"Falkland Islands\", \"es\": \"Islas Malvinas\"}', '{\"en\": \"Falkland Islands\", \"es\": \"Islas Malvinas\"}', '{\"two\": \"fk\", \"three\": \"FLK\"}', '12,173 km²', '.fk'),
(73, 16, NULL, 73, '{\"en\": \"Faroe Islands\", \"es\": \"Islas Feroe\"}', '{\"en\": \"Faroe Islands\", \"es\": \"Islas Feroe\"}', '{\"two\": \"fo\", \"three\": \"FRO\"}', '1,399 km²', '.fo'),
(74, 23, NULL, 74, '{\"en\": \"Micronesia\", \"es\": \"Micronesia\"}', '{\"en\": \"Federated States of Micronesia\", \"es\": \"Estados Federados de Micronesia\"}', '{\"two\": \"fm\", \"three\": \"FSM\"}', '702 km²', '.fm'),
(75, 22, NULL, 75, '{\"en\": \"Fiji\", \"es\": \"Fiyi\"}', '{\"en\": \"Republic of Fiji\", \"es\": \"República de Fiji\"}', '{\"two\": \"fj\", \"three\": \"FJI\"}', '18,274 km²', '.fj'),
(76, 16, NULL, 76, '{\"en\": \"Finland\", \"es\": \"Finlandia\"}', '{\"en\": \"Republic of Finland\", \"es\": \"República de Finlandia\"}', '{\"two\": \"fi\", \"three\": \"FIN\"}', '338,424 km²', '.fi'),
(77, 18, NULL, 77, '{\"en\": \"France\", \"es\": \"Francia\"}', '{\"en\": \"French Republic\", \"es\": \"República Francesa\"}', '{\"two\": \"fr\", \"three\": \"FRA\"}', '643,801 km²', '.fr'),
(78, 6, NULL, 78, '{\"en\": \"French Guiana\", \"es\": \"Guayana Francesa\"}', '{\"en\": \"Guiana\", \"es\": \"Guayana\"}', '{\"two\": \"gf\", \"three\": \"GUF\"}', '83,534 km²', '.gf'),
(79, 24, NULL, 79, '{\"en\": \"French Polynesia\", \"es\": \"Polinesia Francesa\"}', '{\"en\": \"French Polynesia\", \"es\": \"Polinesia Francesa\"}', '{\"two\": \"pf\", \"three\": \"PYF\"}', '3,521 km²', '.pf'),
(80, 2, NULL, 80, '{\"en\": \"Gabon\", \"es\": \"Gabón\"}', '{\"en\": \"Gabonese Republic\", \"es\": \"República Gabonesa\"}', '{\"two\": \"ga\", \"three\": \"GAB\"}', '267,668 km²', '.ga'),
(81, 4, NULL, 81, '{\"en\": \"Gambia\", \"es\": \"Gambia\"}', '{\"en\": \"Republic of the Gambia\", \"es\": \"República de Gambia\"}', '{\"two\": \"gm\", \"three\": \"GMB\"}', '11,295 km²', '.gm'),
(82, 12, NULL, 82, '{\"en\": \"Georgia\", \"es\": \"Georgia\"}', '{\"en\": \"Georgia\", \"es\": \"Georgia\"}', '{\"two\": \"ge\", \"three\": \"GEO\"}', '69,700 km²', '.ge'),
(83, 20, NULL, 83, '{\"en\": \"Germany\", \"es\": \"Alemania\"}', '{\"en\": \"Federal Republic of Germany\", \"es\": \"República Federal de Alemania\"}', '{\"two\": \"de\", \"three\": \"DEU\"}', '357,022 km²', '.de'),
(84, 4, NULL, 84, '{\"en\": \"Ghana\", \"es\": \"Ghana\"}', '{\"en\": \"Republic of Ghana\", \"es\": \"República de Ghana\"}', '{\"two\": \"gh\", \"three\": \"GHA\"}', '238,533 km²', '.gh'),
(85, 18, NULL, 85, '{\"en\": \"Gibraltar\", \"es\": \"Gibraltar\"}', '{\"en\": \"Gibraltar\", \"es\": \"Gibraltar\"}', '{\"two\": \"gi\", \"three\": \"GIB\"}', '6.8 km²', '.gi'),
(86, 17, NULL, 86, '{\"en\": \"Greece\", \"es\": \"Grecia\"}', '{\"en\": \"Hellenic Republic\", \"es\": \"República Helénica\"}', '{\"two\": \"gr\", \"three\": \"GRC\"}', '131,957 km²', '.gr'),
(87, 16, NULL, 87, '{\"en\": \"Greenland\", \"es\": \"Groenlandia\"}', '{\"en\": \"Greenland\", \"es\": \"Groenlandia\"}', '{\"two\": \"gl\", \"three\": \"GRL\"}', '2,166,086 km²', '.gl'),
(88, 7, NULL, 88, '{\"en\": \"Grenada\", \"es\": \"Granada\"}', '{\"en\": \"Grenada\", \"es\": \"Granada\"}', '{\"two\": \"gd\", \"three\": \"GRD\"}', '344 km²', '.gd'),
(89, 7, NULL, 89, '{\"en\": \"Guadeloupe\", \"es\": \"Guadalupe\"}', '{\"en\": \"Guadeloupe\", \"es\": \"Guadalupe\"}', '{\"two\": \"gp\", \"three\": \"GLP\"}', '1,628 km²', '.gp'),
(90, 7, NULL, 90, '{\"en\": \"Guam\", \"es\": \"Guam\"}', '{\"en\": \"Guam\", \"es\": \"Guam\"}', '{\"two\": \"gu\", \"three\": \"GUM\"}', '544 km²', '.gu'),
(91, 9, NULL, 91, '{\"en\": \"Guatemala\", \"es\": \"Guatemala\"}', '{\"en\": \"Republic of Guatemala\", \"es\": \"República de Guatemala\"}', '{\"two\": \"gt\", \"three\": \"GTM\"}', '108,889 km²', '.gt'),
(92, 16, NULL, 92, '{\"en\": \"Guernsey\", \"es\": \"Guernsey\"}', '{\"en\": \"Bailiwick of Guernsey\", \"es\": \"Bailiazgo de Guernsey\"}', '{\"two\": \"gg\", \"three\": \"GGY\"}', '78 km²', '.gg'),
(93, 5, NULL, 93, '{\"en\": \"Guinea\", \"es\": \"Guinea\"}', '{\"en\": \"Republic of Guinea\", \"es\": \"República de Guinea\"}', '{\"two\": \"gn\", \"three\": \"GIN\"}', '245,857 km²', '.gn'),
(94, 5, NULL, 94, '{\"en\": \"Guinea-Bissau\", \"es\": \"Guinea-Bisáu\"}', '{\"en\": \"Republic of Guinea-Bissau\", \"es\": \"República de Guinea-Bisáu\"}', '{\"two\": \"gw\", \"three\": \"GNB\"}', '36,125 km²', '.gw'),
(95, 6, NULL, 95, '{\"en\": \"Guyana\", \"es\": \"Guyana\"}', '{\"en\": \"Co-operative Republic of Guyana\", \"es\": \"República Cooperativa de Guyana\"}', '{\"two\": \"gy\", \"three\": \"GUY\"}', '214,970 km²', '.gy'),
(96, 7, NULL, 96, '{\"en\": \"Haiti\", \"es\": \"Haití\"}', '{\"en\": \"Republic of Haiti\", \"es\": \"República de Haití\"}', '{\"two\": \"ht\", \"three\": \"HTI\"}', '27,750 km²', '.ht'),
(97, 18, NULL, 97, '{\"en\": \"Holy See\", \"es\": \"Santa Sede\"}', '{\"en\": \"Vatican City State\", \"es\": \"Estado de la Ciudad del Vaticano\"}', '{\"two\": \"va\", \"three\": \"VAT\"}', '0.44 km²', '.va'),
(98, 9, NULL, 98, '{\"en\": \"Honduras\", \"es\": \"Honduras\"}', '{\"en\": \"Republic of Honduras\", \"es\": \"República de Honduras\"}', '{\"two\": \"hn\", \"three\": \"HND\"}', '112,492 km²', '.hn'),
(99, 11, NULL, 99, '{\"en\": \"Hong Kong\", \"es\": \"Hong Kong\"}', '{\"en\": \"Hong Kong Special Administrative Region of China\", \"es\": \"Región Administrativa Especial de Hong Kong de China\"}', '{\"two\": \"hk\", \"three\": \"HKG\"}', '1,104 km²', '.hk'),
(100, 20, NULL, 100, '{\"en\": \"Hungary\", \"es\": \"Hungría\"}', '{\"en\": \"Hungary\", \"es\": \"Hungría\"}', '{\"two\": \"hu\", \"three\": \"HUN\"}', '93,028 km²', '.hu'),
(101, 16, NULL, 101, '{\"en\": \"Iceland\", \"es\": \"Islandia\"}', '{\"en\": \"Iceland\", \"es\": \"Islandia\"}', '{\"two\": \"is\", \"three\": \"ISL\"}', '103,000 km²', '.is'),
(102, 13, NULL, 102, '{\"en\": \"India\", \"es\": \"India\"}', '{\"en\": \"Republic of India\", \"es\": \"República de la India\"}', '{\"two\": \"in\", \"three\": \"IND\"}', '3,287,263 km²', '.in'),
(103, 14, NULL, 103, '{\"en\": \"Indonesia\", \"es\": \"Indonesia\"}', '{\"en\": \"Republic of Indonesia\", \"es\": \"República de Indonesia\"}', '{\"two\": \"id\", \"three\": \"IDN\"}', '1,904,569 km²', '.id'),
(104, 12, NULL, 104, '{\"en\": \"Iran\", \"es\": \"Irán\"}', '{\"en\": \"Islamic Republic of Iran\", \"es\": \"República Islámica de Irán\"}', '{\"two\": \"ir\", \"three\": \"IRN\"}', '1,648,195 km²', '.ir'),
(105, 12, NULL, 105, '{\"en\": \"Iraq\", \"es\": \"Irak\"}', '{\"en\": \"Republic of Iraq\", \"es\": \"República de Irak\"}', '{\"two\": \"iq\", \"three\": \"IRQ\"}', '438,317 km²', '.iq'),
(106, 16, NULL, 106, '{\"en\": \"Ireland\", \"es\": \"Irlanda\"}', '{\"en\": \"Ireland\", \"es\": \"Irlanda\"}', '{\"two\": \"ie\", \"three\": \"IRL\"}', '70,273 km²', '.ie'),
(107, 16, NULL, 107, '{\"en\": \"Isle of Man\", \"es\": \"Isla de Man\"}', '{\"en\": \"Isle of Man\", \"es\": \"Isla de Man\"}', '{\"two\": \"im\", \"three\": \"IMN\"}', '572 km²', '.im'),
(108, 12, NULL, 108, '{\"en\": \"Israel\", \"es\": \"Israel\"}', '{\"en\": \"State of Israel\", \"es\": \"Estado de Israel\"}', '{\"two\": \"il\", \"three\": \"ISR\"}', '20,770 km²', '.il'),
(109, 17, NULL, 109, '{\"en\": \"Italy\", \"es\": \"Italia\"}', '{\"en\": \"Italian Republic\", \"es\": \"República Italiana\"}', '{\"two\": \"it\", \"three\": \"ITA\"}', '301,340 km²', '.it'),
(110, 7, NULL, 110, '{\"en\": \"Jamaica\", \"es\": \"Jamaica\"}', '{\"en\": \"Jamaica\", \"es\": \"Jamaica\"}', '{\"two\": \"jm\", \"three\": \"JAM\"}', '10,991 km²', '.jm'),
(111, 11, NULL, 111, '{\"en\": \"Japan\", \"es\": \"Japón\"}', '{\"en\": \"Japan\", \"es\": \"Japón\"}', '{\"two\": \"jp\", \"three\": \"JPN\"}', '377,975 km²', '.jp'),
(112, 16, NULL, 112, '{\"en\": \"Jersey\", \"es\": \"Jersey\"}', '{\"en\": \"Bailiwick of Jersey\", \"es\": \"Bailía de Jersey\"}', '{\"two\": \"je\", \"three\": \"JEY\"}', '46.2 km²', '.je'),
(113, 12, NULL, 113, '{\"en\": \"Jordan\", \"es\": \"Jordania\"}', '{\"en\": \"Hashemite Kingdom of Jordan\", \"es\": \"Reino Hachemita de Jordania\"}', '{\"two\": \"jo\", \"three\": \"JOR\"}', '89,342 km²', '.jo'),
(114, 15, NULL, 114, '{\"en\": \"Kazakhstan\", \"es\": \"Kazajistán\"}', '{\"en\": \"Republic of Kazakhstan\", \"es\": \"República de Kazajistán\"}', '{\"two\": \"kz\", \"three\": \"KAZ\"}', '2,724,900 km²', '.kz'),
(115, 5, NULL, 115, '{\"en\": \"Kenya\", \"es\": \"Kenia\"}', '{\"en\": \"Republic of Kenya\", \"es\": \"República de Kenia\"}', '{\"two\": \"ke\", \"three\": \"KEN\"}', '580,367 km²', '.ke'),
(116, 22, NULL, 116, '{\"en\": \"Kiribati\", \"es\": \"Kiribati\"}', '{\"en\": \"Republic of Kiribati\", \"es\": \"República de Kiribati\"}', '{\"two\": \"ki\", \"three\": \"KIR\"}', '811 km²', '.ki'),
(117, 19, NULL, 117, '{\"en\": \"Kosovo\", \"es\": \"Kosovo\"}', '{\"en\": \"Republic of Kosovo\", \"es\": \"República de Kosovo\"}', '{\"two\": \"xk\", \"three\": \"XKX\"}', '10,887 km²', '.xk'),
(118, 12, NULL, 118, '{\"en\": \"Kuwait\", \"es\": \"Kuwait\"}', '{\"en\": \"State of Kuwait\", \"es\": \"Estado de Kuwait\"}', '{\"two\": \"kw\", \"three\": \"KWT\"}', '17,818 km²', '.kw'),
(119, 15, NULL, 119, '{\"en\": \"Kyrgyzstan\", \"es\": \"Kirguistán\"}', '{\"en\": \"Kyrgyz Republic\", \"es\": \"República de Kirguistán\"}', '{\"two\": \"kg\", \"three\": \"KGZ\"}', '199,951 km²', '.kg'),
(120, 14, NULL, 120, '{\"en\": \"Laos\", \"es\": \"Laos\"}', '{\"en\": \"Lao People\'s Democratic Republic\", \"es\": \"República Democrática Popular Lao\"}', '{\"two\": \"la\", \"three\": \"LAO\"}', '236,800 km²', '.la'),
(121, 16, NULL, 121, '{\"en\": \"Latvia\", \"es\": \"Letonia\"}', '{\"en\": \"Republic of Latvia\", \"es\": \"República de Letonia\"}', '{\"two\": \"lv\", \"three\": \"LVA\"}', '64,589 km²', '.lv'),
(122, 12, NULL, 122, '{\"en\": \"Lebanon\", \"es\": \"Líbano\"}', '{\"en\": \"Lebanese Republic\", \"es\": \"República Libanesa\"}', '{\"two\": \"lb\", \"three\": \"LBN\"}', '10,452 km²', '.lb'),
(123, 5, NULL, 123, '{\"en\": \"Lesotho\", \"es\": \"Lesoto\"}', '{\"en\": \"Kingdom of Lesotho\", \"es\": \"Reino de Lesoto\"}', '{\"two\": \"ls\", \"three\": \"LSO\"}', '30,355 km²', '.ls'),
(124, 5, NULL, 124, '{\"en\": \"Liberia\", \"es\": \"Liberia\"}', '{\"en\": \"Republic of Liberia\", \"es\": \"República de Liberia\"}', '{\"two\": \"lr\", \"three\": \"LBR\"}', '111,369 km²', '.lr'),
(125, 3, NULL, 125, '{\"en\": \"Libya\", \"es\": \"Libia\"}', '{\"en\": \"State of Libya\", \"es\": \"Estado de Libia\"}', '{\"two\": \"ly\", \"three\": \"LBY\"}', '1,759,541 km²', '.ly'),
(126, 16, NULL, 126, '{\"en\": \"Liechtenstein\", \"es\": \"Liechtenstein\"}', '{\"en\": \"Principality of Liechtenstein\", \"es\": \"Principado de Liechtenstein\"}', '{\"two\": \"li\", \"three\": \"LIE\"}', '160 km²', '.li'),
(127, 16, NULL, 127, '{\"en\": \"Lithuania\", \"es\": \"Lituania\"}', '{\"en\": \"Republic of Lithuania\", \"es\": \"República de Lituania\"}', '{\"two\": \"lt\", \"three\": \"LTU\"}', '65,300 km²', '.lt'),
(128, 16, NULL, 128, '{\"en\": \"Luxembourg\", \"es\": \"Luxemburgo\"}', '{\"en\": \"Grand Duchy of Luxembourg\", \"es\": \"Gran Ducado de Luxemburgo\"}', '{\"two\": \"lu\", \"three\": \"LUX\"}', '2,586 km²', '.lu'),
(129, 11, NULL, 129, '{\"en\": \"Macau\", \"es\": \"Macau\"}', '{\"en\": \"Macao Special Administrative Region of the People\'s Republic of China\", \"es\": \"Región Administrativa Especial de Macao de la República Popular China\"}', '{\"two\": \"mo\", \"three\": \"MAC\"}', '32.9 km²', '.mo'),
(130, 5, NULL, 130, '{\"en\": \"Madagascar\", \"es\": \"Madagascar\"}', '{\"en\": \"Republic of Madagascar\", \"es\": \"República de Madagascar\"}', '{\"two\": \"mg\", \"three\": \"MDG\"}', '587,041 km²', '.mg'),
(131, 5, NULL, 131, '{\"en\": \"Malawi\", \"es\": \"Malawi\"}', '{\"en\": \"Republic of Malawi\", \"es\": \"República de Malawi\"}', '{\"two\": \"mw\", \"three\": \"MWI\"}', '118,484 km²', '.mw'),
(132, 14, NULL, 132, '{\"en\": \"Malaysia\", \"es\": \"Malasia\"}', '{\"en\": \"Malaysia\", \"es\": \"Malasia\"}', '{\"two\": \"my\", \"three\": \"MYS\"}', '330,803 km²', '.my'),
(133, 14, NULL, 133, '{\"en\": \"Maldives\", \"es\": \"Maldivas\"}', '{\"en\": \"Republic of Maldives\", \"es\": \"República de Maldivas\"}', '{\"two\": \"mv\", \"three\": \"MDV\"}', '298 km²', '.mv'),
(134, 5, NULL, 134, '{\"en\": \"Mali\", \"es\": \"Malí\"}', '{\"en\": \"Republic of Mali\", \"es\": \"República de Malí\"}', '{\"two\": \"ml\", \"three\": \"MLI\"}', '1,240,192 km²', '.ml'),
(135, 17, NULL, 135, '{\"en\": \"Malta\", \"es\": \"Malta\"}', '{\"en\": \"Republic of Malta\", \"es\": \"República de Malta\"}', '{\"two\": \"mt\", \"three\": \"MLT\"}', '316 km²', '.mt'),
(136, 23, NULL, 136, '{\"en\": \"Marshall Islands\", \"es\": \"Islas Marshall\"}', '{\"en\": \"Republic of the Marshall Islands\", \"es\": \"República de las Islas Marshall\"}', '{\"two\": \"mh\", \"three\": \"MHL\"}', '181.3 km²', '.mh'),
(137, 7, NULL, 137, '{\"en\": \"Martinique\", \"es\": \"Martinica\"}', '{\"en\": \"Martinique\", \"es\": \"Martinica\"}', '{\"two\": \"mq\", \"three\": \"MTQ\"}', '1,128 km²', '.mq'),
(138, 2, NULL, 138, '{\"en\": \"Mauritania\", \"es\": \"Mauritania\"}', '{\"en\": \"Islamic Republic of Mauritania\", \"es\": \"República Islámica de Mauritania\"}', '{\"two\": \"mr\", \"three\": \"MRT\"}', '1,030,700 km²', '.mr'),
(139, 2, NULL, 139, '{\"en\": \"Mauritius\", \"es\": \"Mauricio\"}', '{\"en\": \"Republic of Mauritius\", \"es\": \"República de Mauricio\"}', '{\"two\": \"mu\", \"three\": \"MUS\"}', '2,040 km²', '.mu'),
(140, 2, NULL, 140, '{\"en\": \"Mayotte\", \"es\": \"Mayotte\"}', '{\"en\": \"Mayotte\", \"es\": \"Mayotte\"}', '{\"two\": \"yt\", \"three\": \"MYT\"}', '374 km²', '.yt'),
(141, 9, NULL, 141, '{\"en\": \"Mexico\", \"es\": \"México\"}', '{\"en\": \"United Mexican States\", \"es\": \"Estados Unidos Mexicanos\"}', '{\"two\": \"mx\", \"three\": \"MEX\"}', '1,964,375 km²', '.mx'),
(142, 20, NULL, 142, '{\"en\": \"Moldova\", \"es\": \"Moldavia\"}', '{\"en\": \"Republic of Moldova\", \"es\": \"República de Moldavia\"}', '{\"two\": \"md\", \"three\": \"MDA\"}', '33,851 km²', '.md'),
(143, 18, NULL, 143, '{\"en\": \"Monaco\", \"es\": \"Mónaco\"}', '{\"en\": \"Principality of Monaco\", \"es\": \"Principado de Mónaco\"}', '{\"two\": \"mc\", \"three\": \"MCO\"}', '2.02 km²', '.mc'),
(144, 15, NULL, 144, '{\"en\": \"Mongolia\", \"es\": \"Mongolia\"}', '{\"en\": \"Mongolia\", \"es\": \"Mongolia\"}', '{\"two\": \"mn\", \"three\": \"MNG\"}', '1,564,116 km²', '.mn'),
(145, 19, NULL, 145, '{\"en\": \"Montenegro\", \"es\": \"Montenegro\"}', '{\"en\": \"Montenegro\", \"es\": \"Montenegro\"}', '{\"two\": \"me\", \"three\": \"MNE\"}', '13,812 km²', '.me'),
(146, 7, NULL, 146, '{\"en\": \"Montserrat\", \"es\": \"Montserrat\"}', '{\"en\": \"Montserrat\", \"es\": \"Montserrat\"}', '{\"two\": \"ms\", \"three\": \"MSR\"}', '102,000 km²', '.ms'),
(147, 3, NULL, 147, '{\"en\": \"Morocco\", \"es\": \"Marruecos\"}', '{\"en\": \"Kingdom of Morocco\", \"es\": \"Reino de Marruecos\"}', '{\"two\": \"ma\", \"three\": \"MAR\"}', '710,850 km²', '.ma'),
(148, 5, NULL, 148, '{\"en\": \"Mozambique\", \"es\": \"Mozambique\"}', '{\"en\": \"Republic of Mozambique\", \"es\": \"República de Mozambique\"}', '{\"two\": \"mz\", \"three\": \"MOZ\"}', '801,590 km²', '.mz'),
(149, 14, NULL, 149, '{\"en\": \"Myanmar\", \"es\": \"Myanmar\"}', '{\"en\": \"Republic of the Union of Myanmar\", \"es\": \"República de la Unión de Myanmar\"}', '{\"two\": \"mm\", \"three\": \"MMR\"}', '676,578 km²', '.mm'),
(150, 1, NULL, 150, '{\"en\": \"Namibia\", \"es\": \"Namibia\"}', '{\"en\": \"Republic of Namibia\", \"es\": \"República de Namibia\"}', '{\"two\": \"na\", \"three\": \"NAM\"}', '825,615 km²', '.na'),
(151, 22, NULL, 151, '{\"en\": \"Nauru\", \"es\": \"Nauru\"}', '{\"en\": \"Republic of Nauru\", \"es\": \"República de Nauru\"}', '{\"two\": \"nr\", \"three\": \"NRU\"}', '21 km²', '.nr'),
(152, 13, NULL, 152, '{\"en\": \"Nepal\", \"es\": \"Nepal\"}', '{\"en\": \"Federal Democratic Republic of Nepal\", \"es\": \"República Democrática Federal de Nepal\"}', '{\"two\": \"np\", \"three\": \"NPL\"}', '147,516 km²', '.np'),
(153, 16, NULL, 153, '{\"en\": \"Netherlands\", \"es\": \"Países Bajos\"}', '{\"en\": \"Kingdom of the Netherlands\", \"es\": \"Reino de los Países Bajos\"}', '{\"two\": \"nl\", \"three\": \"NLD\"}', '41,543 km²', '.nl'),
(154, 22, NULL, 154, '{\"en\": \"New Caledonia\", \"es\": \"Nueva Caledonia\"}', '{\"en\": \"New Caledonia\", \"es\": \"Nueva Caledonia\"}', '{\"two\": \"nc\", \"three\": \"NCL\"}', '18,576 km²', '.nc'),
(155, 25, NULL, 155, '{\"en\": \"New Zealand\", \"es\": \"Nueva Zelanda\"}', '{\"en\": \"New Zealand\", \"es\": \"Nueva Zelanda\"}', '{\"two\": \"nz\", \"three\": \"NZL\"}', '268,021 km²', '.nz'),
(156, 9, NULL, 156, '{\"en\": \"Nicaragua\", \"es\": \"Nicaragua\"}', '{\"en\": \"Republic of Nicaragua\", \"es\": \"República de Nicaragua\"}', '{\"two\": \"ni\", \"three\": \"NIC\"}', '130,375 km²', '.ni'),
(157, 4, NULL, 157, '{\"en\": \"Niger\", \"es\": \"Níger\"}', '{\"en\": \"Republic of the Niger\", \"es\": \"República del Níger\"}', '{\"two\": \"ne\", \"three\": \"NER\"}', '1,267,000 km²', '.ne'),
(158, 4, NULL, 158, '{\"en\": \"Nigeria\", \"es\": \"Nigeria\"}', '{\"en\": \"Federal Republic of Nigeria\", \"es\": \"República Federal de Nigeria\"}', '{\"two\": \"ng\", \"three\": \"NGA\"}', '923,768 km²', '.ng'),
(159, 23, NULL, 159, '{\"en\": \"Niue\", \"es\": \"Niue\"}', '{\"en\": \"Niue\", \"es\": \"Niue\"}', '{\"two\": \"nu\", \"three\": \"NIU\"}', '260 km²', '.nu'),
(160, 22, NULL, 160, '{\"en\": \"Norfolk Island\", \"es\": \"Isla Norfolk\"}', '{\"en\": \"Norfolk Island\", \"es\": \"Isla Norfolk\"}', '{\"two\": \"nf\", \"three\": \"NFK\"}', '36 km²', '.nf'),
(161, 11, NULL, 161, '{\"en\": \"North Korea\", \"es\": \"Corea del Norte\"}', '{\"en\": \"Democratic People\'s Republic of Korea\", \"es\": \"República Popular Democrática de Corea\"}', '{\"two\": \"kp\", \"three\": \"PRK\"}', '120,540 km²', '.kp'),
(162, 19, NULL, 162, '{\"en\": \"North Macedonia\", \"es\": \"Macedonia del Norte\"}', '{\"en\": \"Republic of North Macedonia\", \"es\": \"República de Macedonia del Norte\"}', '{\"two\": \"mk\", \"three\": \"MKD\"}', '25,713 km²', '.mk'),
(163, 16, NULL, 163, '{\"en\": \"Northern Ireland\", \"es\": \"Irlanda del Norte\"}', '{\"en\": \"Northern Ireland\", \"es\": \"Irlanda del Norte\"}', '{\"two\": \"gb-nir\", \"three\": \"GB-NIR\"}', '14,130 km²', '.gb'),
(164, 23, NULL, 164, '{\"en\": \"Northern Mariana Islands\", \"es\": \"Islas Marianas del Norte\"}', '{\"en\": \"Commonwealth of the Northern Mariana Islands\", \"es\": \"Mancomunidad de las Islas Marianas del Norte\"}', '{\"two\": \"mp\", \"three\": \"MNP\"}', '464 km²', '.mp'),
(165, 16, NULL, 165, '{\"en\": \"Norway\", \"es\": \"Noruega\"}', '{\"en\": \"Kingdom of Norway\", \"es\": \"Reino de Noruega\"}', '{\"two\": \"no\", \"three\": \"NOR\"}', '148,729 km²', '.no'),
(166, 12, NULL, 166, '{\"en\": \"Oman\", \"es\": \"Omán\"}', '{\"en\": \"Sultanate of Oman\", \"es\": \"Sultanato de Omán\"}', '{\"two\": \"om\", \"three\": \"OMN\"}', '309,500 km²', '.om'),
(167, 12, NULL, 167, '{\"en\": \"Pakistan\", \"es\": \"Pakistán\"}', '{\"en\": \"Islamic Republic of Pakistan\", \"es\": \"República Islámica de Pakistán\"}', '{\"two\": \"pk\", \"three\": \"PAK\"}', '881,913 km²', '.pk'),
(168, 22, NULL, 168, '{\"en\": \"Palau\", \"es\": \"Palau\"}', '{\"en\": \"Republic of Palau\", \"es\": \"República de Palau\"}', '{\"two\": \"pw\", \"three\": \"PLW\"}', '459 km²', '.pw'),
(169, 9, NULL, 169, '{\"en\": \"Panama\", \"es\": \"Panamá\"}', '{\"en\": \"Republic of Panama\", \"es\": \"República de Panamá\"}', '{\"two\": \"pa\", \"three\": \"PAN\"}', '75,517 km²', '.pa'),
(170, 22, NULL, 170, '{\"en\": \"Papua New Guinea\", \"es\": \"Papúa Nueva Guinea\"}', '{\"en\": \"Independent State of Papua New Guinea\", \"es\": \"Estado Independiente de Papúa Nueva Guinea\"}', '{\"two\": \"pg\", \"three\": \"PNG\"}', '462,840 km²', '.pg'),
(171, 6, NULL, 171, '{\"en\": \"Paraguay\", \"es\": \"Paraguay\"}', '{\"en\": \"Republic of Paraguay\", \"es\": \"República del Paraguay\"}', '{\"two\": \"py\", \"three\": \"PRY\"}', '406,752 km²', '.py'),
(172, 6, NULL, 172, '{\"en\": \"Peru\", \"es\": \"Perú\"}', '{\"en\": \"Republic of Peru\", \"es\": \"República del Perú\"}', '{\"two\": \"pe\", \"three\": \"PER\"}', '1,285,216 km²', '.pe'),
(173, 14, NULL, 173, '{\"en\": \"Philippines\", \"es\": \"Filipinas\"}', '{\"en\": \"Republic of the Philippines\", \"es\": \"República de Filipinas\"}', '{\"two\": \"ph\", \"three\": \"PHL\"}', '300,000 km²', '.ph'),
(174, 22, NULL, 174, '{\"en\": \"Pitcairn\", \"es\": \"Pitcairn\"}', '{\"en\": \"Pitcairn Islands\", \"es\": \"Islas Pitcairn\"}', '{\"two\": \"pn\", \"three\": \"PCN\"}', '47 km²', '.pn'),
(175, 20, NULL, 175, '{\"en\": \"Poland\", \"es\": \"Polonia\"}', '{\"en\": \"Republic of Poland\", \"es\": \"República de Polonia\"}', '{\"two\": \"pl\", \"three\": \"POL\"}', '312,696 km²', '.pl'),
(176, 18, NULL, 176, '{\"en\": \"Portugal\", \"es\": \"Portugal\"}', '{\"en\": \"Portuguese Republic\", \"es\": \"República Portuguesa\"}', '{\"two\": \"pt\", \"three\": \"PRT\"}', '92,090 km²', '.pt'),
(177, 7, NULL, 177, '{\"en\": \"Puerto Rico\", \"es\": \"Puerto Rico\"}', '{\"en\": \"Territory of Puerto Rico\", \"es\": \"Territorio de Puerto Rico\"}', '{\"two\": \"pr\", \"three\": \"PRI\"}', '9,104 km²', '.pr'),
(178, 12, NULL, 178, '{\"en\": \"Qatar\", \"es\": \"Catar\"}', '{\"en\": \"State of Qatar\", \"es\": \"Estado de Catar\"}', '{\"two\": \"qa\", \"three\": \"QAT\"}', '11,586 km²', '.qa'),
(179, 5, NULL, 179, '{\"en\": \"Republic of the Congo\", \"es\": \"República del Congo\"}', '{\"en\": \"Republic of the Congo\", \"es\": \"República del Congo\"}', '{\"two\": \"cg\", \"three\": \"COG\"}', '342,000 km²', '.cg'),
(180, 20, NULL, 180, '{\"en\": \"Romania\", \"es\": \"Rumanía\"}', '{\"en\": \"Romania\", \"es\": \"Rumanía\"}', '{\"two\": \"ro\", \"three\": \"ROU\"}', '238,397 km²', '.ro'),
(181, 21, NULL, 181, '{\"en\": \"Russia\", \"es\": \"Rusia\"}', '{\"en\": \"Russian Federation\", \"es\": \"Federación Rusa\"}', '{\"two\": \"ru\", \"three\": \"RUS\"}', '17,098,242 km²', '.ru'),
(182, 5, NULL, 182, '{\"en\": \"Rwanda\", \"es\": \"Ruanda\"}', '{\"en\": \"Republic of Rwanda\", \"es\": \"República de Ruanda\"}', '{\"two\": \"rw\", \"three\": \"RWA\"}', '26,338 km²', '.rw'),
(183, 5, NULL, 183, '{\"en\": \"Réunion\", \"es\": \"Reunión\"}', '{\"en\": \"Réunion\", \"es\": \"Reunión\"}', '{\"two\": \"re\", \"three\": \"REU\"}', '2,512 km²', '.re'),
(184, 7, NULL, 184, '{\"en\": \"Saint Barthélemy\", \"es\": \"San Bartolomé\"}', '{\"en\": \"Collectivity of Saint Barthélemy\", \"es\": \"Colectividad de San Bartolomé\"}', '{\"two\": \"bl\", \"three\": \"BLM\"}', '25 km²', '.bl'),
(185, 22, NULL, 185, '{\"en\": \"Saint Helena\", \"es\": \"Santa Elena\"}', '{\"en\": \"Saint Helena\", \"es\": \"Santa Elena\"}', '{\"two\": \"sh-hl\", \"three\": \"SHN\"}', '122 km²', '.sh'),
(186, 22, NULL, 186, '{\"en\": \"Saint Helena, Ascension and Tristan da Cunha\", \"es\": \"Santa Elena, Ascensión y Tristán de Acuña\"}', '{\"en\": \"Saint Helena, Ascension and Tristan da Cunha\", \"es\": \"Santa Elena, Ascensión y Tristán de Acuña\"}', '{\"two\": \"sh\", \"three\": \"SHN\"}', '394 km²', '.sh'),
(187, 7, NULL, 187, '{\"en\": \"Saint Kitts and Nevis\", \"es\": \"San Cristóbal y Nieves\"}', '{\"en\": \"Federation of Saint Kitts and Nevis\", \"es\": \"Federación de San Cristóbal y Nieves\"}', '{\"two\": \"kn\", \"three\": \"KNA\"}', '261 km²', '.kn'),
(188, 7, NULL, 188, '{\"en\": \"Saint Lucia\", \"es\": \"Santa Lucía\"}', '{\"en\": \"Saint Lucia\", \"es\": \"Santa Lucía\"}', '{\"two\": \"lc\", \"three\": \"LCA\"}', '616 km²', '.lc'),
(189, 7, NULL, 189, '{\"en\": \"Saint Martin\", \"es\": \"San Martín\"}', '{\"en\": \"Saint Martin\", \"es\": \"San Martín\"}', '{\"two\": \"mf\", \"three\": \"MAF\"}', '53 km²', '.mf'),
(190, 7, NULL, 190, '{\"en\": \"Saint Pierre and Miquelon\", \"es\": \"San Pedro y Miquelón\"}', '{\"en\": \"Saint Pierre and Miquelon\", \"es\": \"San Pedro y Miquelón\"}', '{\"two\": \"pm\", \"three\": \"SPM\"}', '242 km²', '.pm'),
(191, 7, NULL, 191, '{\"en\": \"Saint Vincent and the Grenadines\", \"es\": \"San Vicente y las Granadinas\"}', '{\"en\": \"Saint Vincent and the Grenadines\", \"es\": \"San Vicente y las Granadinas\"}', '{\"two\": \"vc\", \"three\": \"VCT\"}', '389 km²', '.vc'),
(192, 22, NULL, 192, '{\"en\": \"Samoa\", \"es\": \"Samoa\"}', '{\"en\": \"Independent State of Samoa\", \"es\": \"Estado Independiente de Samoa\"}', '{\"two\": \"ws\", \"three\": \"WSM\"}', '2,831 km²', '.ws'),
(193, 17, NULL, 193, '{\"en\": \"San Marino\", \"es\": \"San Marino\"}', '{\"en\": \"Most Serene Republic of San Marino\", \"es\": \"República Serenísima de San Marino\"}', '{\"two\": \"sm\", \"three\": \"SMR\"}', '61 km²', '.sm'),
(194, 2, NULL, 194, '{\"en\": \"Sao Tome and Principe\", \"es\": \"Santo Tomé y Príncipe\"}', '{\"en\": \"Democratic Republic of São Tomé and Príncipe\", \"es\": \"República Democrática de Santo Tomé y Príncipe\"}', '{\"two\": \"st\", \"three\": \"STP\"}', '964 km²', '.st'),
(195, 12, NULL, 195, '{\"en\": \"Saudi Arabia\", \"es\": \"Arabia Saudita\"}', '{\"en\": \"Kingdom of Saudi Arabia\", \"es\": \"Reino de Arabia Saudita\"}', '{\"two\": \"sa\", \"three\": \"SAU\"}', '2,150,000 km²', '.sa'),
(196, 16, NULL, 196, '{\"en\": \"Scotland\", \"es\": \"Escocia\"}', '{\"en\": \"Scotland\", \"es\": \"Escocia\"}', '{\"two\": \"gb-sct\", \"three\": \"GB-SCT\"}', '77,910 km²', '.scot'),
(197, 4, NULL, 197, '{\"en\": \"Senegal\", \"es\": \"Senegal\"}', '{\"en\": \"Republic of Senegal\", \"es\": \"República de Senegal\"}', '{\"two\": \"sn\", \"three\": \"SEN\"}', '196,722 km²', '.sn'),
(198, 19, NULL, 198, '{\"en\": \"Serbia\", \"es\": \"Serbia\"}', '{\"en\": \"Republic of Serbia\", \"es\": \"República de Serbia\"}', '{\"two\": \"rs\", \"three\": \"SRB\"}', '77,474 km²', '.rs'),
(199, 22, NULL, 199, '{\"en\": \"Seychelles\", \"es\": \"Seychelles\"}', '{\"en\": \"Republic of Seychelles\", \"es\": \"República de Seychelles\"}', '{\"two\": \"sc\", \"three\": \"SYC\"}', '455 km²', '.sc'),
(200, 5, NULL, 200, '{\"en\": \"Sierra Leone\", \"es\": \"Sierra Leona\"}', '{\"en\": \"Republic of Sierra Leone\", \"es\": \"República de Sierra Leona\"}', '{\"two\": \"sl\", \"three\": \"SLE\"}', '71,740 km²', '.sl'),
(201, 14, NULL, 201, '{\"en\": \"Singapore\", \"es\": \"Singapur\"}', '{\"en\": \"Republic of Singapore\", \"es\": \"República de Singapur\"}', '{\"two\": \"sg\", \"three\": \"SGP\"}', '728.6 km²', '.sg'),
(202, 7, NULL, 202, '{\"en\": \"Sint Maarten\", \"es\": \"Sint Maarten\"}', '{\"en\": \"Sint Maarten\", \"es\": \"Sint Maarten\"}', '{\"two\": \"sx\", \"three\": \"SXM\"}', '34 km²', '.sx'),
(203, 20, NULL, 203, '{\"en\": \"Slovakia\", \"es\": \"Eslovaquia\"}', '{\"en\": \"Slovak Republic\", \"es\": \"República Eslovaca\"}', '{\"two\": \"sk\", \"three\": \"SVK\"}', '49,035 km²', '.sk'),
(204, 20, NULL, 204, '{\"en\": \"Slovenia\", \"es\": \"Eslovenia\"}', '{\"en\": \"Republic of Slovenia\", \"es\": \"República de Eslovenia\"}', '{\"two\": \"si\", \"three\": \"SVN\"}', '20,273 km²', '.si'),
(205, 22, NULL, 205, '{\"en\": \"Solomon Islands\", \"es\": \"Islas Salomón\"}', '{\"en\": \"Solomon Islands\", \"es\": \"Islas Salomón\"}', '{\"two\": \"sb\", \"three\": \"SLB\"}', '28,896 km²', '.sb'),
(206, 5, NULL, 206, '{\"en\": \"Somalia\", \"es\": \"Somalia\"}', '{\"en\": \"Federal Republic of Somalia\", \"es\": \"República Federal de Somalia\"}', '{\"two\": \"so\", \"three\": \"SOM\"}', '637,657 km²', '.so'),
(207, 1, NULL, 207, '{\"en\": \"South Africa\", \"es\": \"Sudáfrica\"}', '{\"en\": \"Republic of South Africa\", \"es\": \"República de Sudáfrica\"}', '{\"two\": \"za\", \"three\": \"ZAF\"}', '1,221,037 km²', '.za'),
(208, 14, NULL, 208, '{\"en\": \"South Korea\", \"es\": \"Corea del Sur\"}', '{\"en\": \"Republic of Korea\", \"es\": \"República de Corea\"}', '{\"two\": \"kr\", \"three\": \"KOR\"}', '100,210 km²', '.kr'),
(209, 5, NULL, 209, '{\"en\": \"South Sudan\", \"es\": \"Sudán del Sur\"}', '{\"en\": \"Republic of South Sudan\", \"es\": \"República de Sudán del Sur\"}', '{\"two\": \"ss\", \"three\": \"SSD\"}', '619,745 km²', '.ss'),
(210, 17, NULL, 210, '{\"en\": \"Spain\", \"es\": \"España\"}', '{\"en\": \"Kingdom of Spain\", \"es\": \"Reino de España\"}', '{\"two\": \"es\", \"three\": \"ESP\"}', '505,990 km²', '.es'),
(211, 13, NULL, 211, '{\"en\": \"Sri Lanka\", \"es\": \"Sri Lanka\"}', '{\"en\": \"Democratic Socialist Republic of Sri Lanka\", \"es\": \"República Socialista Democrática de Sri Lanka\"}', '{\"two\": \"lk\", \"three\": \"LKA\"}', '65,610 km²', '.lk'),
(212, 12, NULL, 212, '{\"en\": \"State of Palestine\", \"es\": \"Estado de Palestina\"}', '{\"en\": \"State of Palestine\", \"es\": \"Estado de Palestina\"}', '{\"two\": \"ps\", \"three\": \"PSE\"}', '6,020 km²', '.ps'),
(213, 5, NULL, 213, '{\"en\": \"Sudan\", \"es\": \"Sudán\"}', '{\"en\": \"Republic of the Sudan\", \"es\": \"República del Sudán\"}', '{\"two\": \"sd\", \"three\": \"SDN\"}', '1,861,484 km²', '.sd'),
(214, 6, NULL, 214, '{\"en\": \"Suriname\", \"es\": \"Surinam\"}', '{\"en\": \"Republic of Suriname\", \"es\": \"República de Surinam\"}', '{\"two\": \"sr\", \"three\": \"SUR\"}', '163,820 km²', '.sr'),
(215, 16, NULL, 215, '{\"en\": \"Sweden\", \"es\": \"Suecia\"}', '{\"en\": \"Kingdom of Sweden\", \"es\": \"Reino de Suecia\"}', '{\"two\": \"se\", \"three\": \"SWE\"}', '450,295 km²', '.se'),
(216, 16, NULL, 216, '{\"en\": \"Switzerland\", \"es\": \"Suiza\"}', '{\"en\": \"Swiss Confederation\", \"es\": \"Confederación Suiza\"}', '{\"two\": \"ch\", \"three\": \"CHE\"}', '41,290 km²', '.ch'),
(217, 12, NULL, 217, '{\"en\": \"Syria\", \"es\": \"Siria\"}', '{\"en\": \"Syrian Arab Republic\", \"es\": \"República Árabe Siria\"}', '{\"two\": \"sy\", \"three\": \"SYR\"}', '185,180 km²', '.sy'),
(218, 14, NULL, 218, '{\"en\": \"Taiwan\", \"es\": \"Taiwán\"}', '{\"en\": \"Republic of China\", \"es\": \"República de China\"}', '{\"two\": \"tw\", \"three\": \"TWN\"}', '36,197 km²', '.tw'),
(219, 15, NULL, 219, '{\"en\": \"Tajikistan\", \"es\": \"Tayikistán\"}', '{\"en\": \"Republic of Tajikistan\", \"es\": \"República de Tayikistán\"}', '{\"two\": \"tj\", \"three\": \"TJK\"}', '143,100 km²', '.tj'),
(220, 5, NULL, 220, '{\"en\": \"Tanzania\", \"es\": \"Tanzania\"}', '{\"en\": \"United Republic of Tanzania\", \"es\": \"República Unida de Tanzania\"}', '{\"two\": \"tz\", \"three\": \"TZA\"}', '945,087 km²', '.tz'),
(221, 14, NULL, 221, '{\"en\": \"Thailand\", \"es\": \"Tailandia\"}', '{\"en\": \"Kingdom of Thailand\", \"es\": \"Reino de Tailandia\"}', '{\"two\": \"th\", \"three\": \"THA\"}', '513,120 km²', '.th'),
(222, 14, NULL, 222, '{\"en\": \"Timor-Leste\", \"es\": \"Timor-Leste\"}', '{\"en\": \"Democratic Republic of Timor-Leste\", \"es\": \"República Democrática de Timor-Leste\"}', '{\"two\": \"tl\", \"three\": \"TLS\"}', '14,874 km²', '.tl'),
(223, 4, NULL, 223, '{\"en\": \"Togo\", \"es\": \"Togo\"}', '{\"en\": \"Togolese Republic\", \"es\": \"República Togolesa\"}', '{\"two\": \"tg\", \"three\": \"TGO\"}', '56,785 km²', '.tg'),
(224, 22, NULL, 224, '{\"en\": \"Tokelau\", \"es\": \"Tokelau\"}', '{\"en\": \"Tokelau\", \"es\": \"Tokelau\"}', '{\"two\": \"tk\", \"three\": \"TKL\"}', '12 km²', '.tk'),
(225, 22, NULL, 225, '{\"en\": \"Tonga\", \"es\": \"Tonga\"}', '{\"en\": \"Kingdom of Tonga\", \"es\": \"Reino de Tonga\"}', '{\"two\": \"to\", \"three\": \"TON\"}', '748 km²', '.to'),
(226, 7, NULL, 226, '{\"en\": \"Trinidad and Tobago\", \"es\": \"Trinidad y Tobago\"}', '{\"en\": \"Republic of Trinidad and Tobago\", \"es\": \"República de Trinidad y Tobago\"}', '{\"two\": \"tt\", \"three\": \"TTO\"}', '5,128 km²', '.tt'),
(227, 3, NULL, 227, '{\"en\": \"Tunisia\", \"es\": \"Túnez\"}', '{\"en\": \"Tunisian Republic\", \"es\": \"República Tunecina\"}', '{\"two\": \"tn\", \"three\": \"TUN\"}', '163,610 km²', '.tn'),
(228, 15, NULL, 228, '{\"en\": \"Turkmenistan\", \"es\": \"Turkmenistán\"}', '{\"en\": \"Turkmenistan\", \"es\": \"Turkmenistán\"}', '{\"two\": \"tm\", \"three\": \"TKM\"}', '491,210 km²', '.tm'),
(229, 7, NULL, 229, '{\"en\": \"Turks and Caicos Islands\", \"es\": \"Islas Turcas y Caicos\"}', '{\"en\": \"Turks and Caicos Islands\", \"es\": \"Islas Turcas y Caicos\"}', '{\"two\": \"tc\", \"three\": \"TCA\"}', '948 km²', '.tc'),
(230, 22, NULL, 230, '{\"en\": \"Tuvalu\", \"es\": \"Tuvalu\"}', '{\"en\": \"Tuvalu\", \"es\": \"Tuvalu\"}', '{\"two\": \"tv\", \"three\": \"TUV\"}', '26 km²', '.tv'),
(231, 12, NULL, 231, '{\"en\": \"Türkiye\", \"es\": \"Turquía\"}', '{\"en\": \"Republic of Türkiye\", \"es\": \"República de Turquía\"}', '{\"two\": \"tr\", \"three\": \"TUR\"}', '783,356 km²', '.tr'),
(232, 5, NULL, 232, '{\"en\": \"Uganda\", \"es\": \"Uganda\"}', '{\"en\": \"Republic of Uganda\", \"es\": \"República de Uganda\"}', '{\"two\": \"ug\", \"three\": \"UGA\"}', '241,038 km²', '.ug'),
(233, 21, NULL, 233, '{\"en\": \"Ukraine\", \"es\": \"Ucrania\"}', '{\"en\": \"Ukraine\", \"es\": \"Ucrania\"}', '{\"two\": \"ua\", \"three\": \"UKR\"}', '603,550 km²', '.ua'),
(234, 12, NULL, 234, '{\"en\": \"United Arab Emirates\", \"es\": \"Emiratos Árabes Unidos\"}', '{\"en\": \"United Arab Emirates\", \"es\": \"Emiratos Árabes Unidos\"}', '{\"two\": \"ae\", \"three\": \"ARE\"}', '83,600 km²', '.ae'),
(235, 16, NULL, 235, '{\"en\": \"United Kingdom\", \"es\": \"Reino Unido\"}', '{\"en\": \"United Kingdom of Great Britain and Northern Ireland\", \"es\": \"Reino Unido de Gran Bretaña e Irlanda del Norte\"}', '{\"two\": \"gb\", \"three\": \"GBR\"}', '243,610 km²', '.uk'),
(236, 8, NULL, 236, '{\"en\": \"United States of America\", \"es\": \"Estados Unidos de América\"}', '{\"en\": \"United States of America\", \"es\": \"Estados Unidos de América\"}', '{\"two\": \"us\", \"three\": \"USA\"}', '9,631,418 km²', '.us'),
(237, 6, NULL, 237, '{\"en\": \"Uruguay\", \"es\": \"Uruguay\"}', '{\"en\": \"Oriental Republic of Uruguay\", \"es\": \"República Oriental del Uruguay\"}', '{\"two\": \"uy\", \"three\": \"URY\"}', '176,215 km²', '.uy'),
(238, 15, NULL, 238, '{\"en\": \"Uzbekistan\", \"es\": \"Uzbekistán\"}', '{\"en\": \"Republic of Uzbekistan\", \"es\": \"República de Uzbekistán\"}', '{\"two\": \"uz\", \"three\": \"UZB\"}', '447,400 km²', '.uz'),
(239, 22, NULL, 239, '{\"en\": \"Vanuatu\", \"es\": \"Vanuatu\"}', '{\"en\": \"Republic of Vanuatu\", \"es\": \"República de Vanuatu\"}', '{\"two\": \"vu\", \"three\": \"VUT\"}', '12,189 km²', '.vu'),
(240, 6, NULL, 240, '{\"en\": \"Venezuela\", \"es\": \"Venezuela\"}', '{\"en\": \"Bolivarian Republic of Venezuela\", \"es\": \"República Bolivariana de Venezuela\"}', '{\"two\": \"ve\", \"three\": \"VEN\"}', '912,050 km²', '.ve'),
(241, 14, NULL, 241, '{\"en\": \"Vietnam\", \"es\": \"Vietnam\"}', '{\"en\": \"Socialist Republic of Vietnam\", \"es\": \"República Socialista de Vietnam\"}', '{\"two\": \"vn\", \"three\": \"VNM\"}', '331,210 km²', '.vn'),
(242, 7, NULL, 242, '{\"en\": \"Virgin Islands (British)\", \"es\": \"Islas Vírgenes Británicas\"}', '{\"en\": \"British Virgin Islands\", \"es\": \"Islas Vírgenes Británicas\"}', '{\"two\": \"vg\", \"three\": \"VGB\"}', '151 km²', '.vg'),
(243, 7, NULL, 243, '{\"en\": \"Virgin Islands (U.S.)\", \"es\": \"Islas Vírgenes de los EE. UU.\"}', '{\"en\": \"United States Virgin Islands\", \"es\": \"Islas Vírgenes de los Estados Unidos\"}', '{\"two\": \"vi\", \"three\": \"VIR\"}', '352 km²', '.vi');
INSERT INTO `geo_countries` (`id`, `id_region`, `id_capital`, `id_flag`, `popular_name`, `official_name`, `abbreviation`, `surface_area`, `tld`) VALUES
(244, 22, NULL, 244, '{\"en\": \"Wallis and Futuna\", \"es\": \"Wallis y Futuna\"}', '{\"en\": \"Territory of Wallis and Futuna\", \"es\": \"Territorio de Wallis y Futuna\"}', '{\"two\": \"wf\", \"three\": \"WLF\"}', '142 km²', '.wf'),
(245, 12, NULL, 245, '{\"en\": \"Yemen\", \"es\": \"Yemen\"}', '{\"en\": \"Republic of Yemen\", \"es\": \"República de Yemen\"}', '{\"two\": \"ye\", \"three\": \"YEM\"}', '527,968 km²', '.ye'),
(246, 5, NULL, 246, '{\"en\": \"Zambia\", \"es\": \"Zambia\"}', '{\"en\": \"Republic of Zambia\", \"es\": \"República de Zambia\"}', '{\"two\": \"zm\", \"three\": \"ZMB\"}', '752,612 km²', '.zm'),
(247, 5, NULL, 247, '{\"en\": \"Zimbabwe\", \"es\": \"Zimbabue\"}', '{\"en\": \"Republic of Zimbabwe\", \"es\": \"República de Zimbabue\"}', '{\"two\": \"zw\", \"three\": \"ZWE\"}', '390,757 km²', '.zw');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_countries_has_currencies`
--

CREATE TABLE `geo_countries_has_currencies` (
  `id` int NOT NULL COMMENT 'Unique identifier for each country/currency relationship.',
  `country_id` int NOT NULL COMMENT 'Country ID.',
  `currency_id` int NOT NULL COMMENT 'Currency ID.',
  `example` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Example of how the number is normally displayed in the country.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship between countries and their currencies.';

--
-- Volcado de datos para la tabla `geo_countries_has_currencies`
--

INSERT INTO `geo_countries_has_currencies` (`id`, `country_id`, `currency_id`, `example`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, 1, '؋1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(2, 2, 3, '1,234.56 Lek', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(3, 3, 40, '1,234.56 دج', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(4, 4, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(5, 5, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(6, 6, 6, 'Kz 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(7, 7, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(8, 8, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(9, 9, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(10, 10, 7, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(11, 11, 4, '֏1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(12, 12, 9, 'ƒ1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(13, 13, 124, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(14, 14, 8, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(15, 15, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(16, 16, 10, '₼1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(17, 17, 21, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(18, 18, 15, '.د.ب1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(19, 19, 13, '৳1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(20, 20, 12, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(21, 21, 24, 'Br 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(22, 22, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(23, 23, 25, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(24, 24, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(25, 25, 17, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(26, 26, 22, 'Nu.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(27, 27, 19, 'Bs.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(28, 28, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(29, 29, 11, 'KM 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(30, 30, 23, 'P 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(31, 31, 20, 'R$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(32, 32, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(33, 33, 18, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(34, 34, 14, 'лв 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(35, 35, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(36, 36, 16, 'Fr 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(37, 37, 35, 'Esc 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(38, 38, 72, '៛1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(39, 39, 149, 'FCFA 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(40, 40, 26, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(41, 41, 77, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(42, 42, 149, 'FCFA 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(43, 43, 149, 'FCFA 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(44, 44, 29, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(45, 45, 30, '¥1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(46, 46, 8, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(47, 47, 8, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(48, 48, 31, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(49, 49, 73, 'CF 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(50, 50, 104, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(51, 51, 32, '₡1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(52, 52, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(53, 53, 34, '₱1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(54, 54, 5, 'ƒ1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(55, 55, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(56, 56, 36, 'Kč 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(57, 57, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(58, 58, 27, 'FC 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(59, 59, 38, 'kr 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(60, 60, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(61, 61, 37, 'Fdj 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(62, 62, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(63, 63, 39, 'RD$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(64, 64, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(65, 65, 41, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(66, 66, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(67, 67, 149, 'FCFA 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(68, 68, 42, 'Nfk 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(69, 69, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(70, 70, 130, 'E 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(71, 71, 43, 'ብር1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(72, 72, 46, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(73, 73, 38, 'kr 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(74, 74, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(75, 75, 45, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(76, 76, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(77, 77, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(78, 78, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(79, 79, 152, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(80, 80, 149, 'FCFA 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(81, 81, 52, 'D 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(82, 82, 48, '₾1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(83, 83, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(84, 84, 50, '₵1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(85, 85, 51, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(86, 86, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(87, 87, 38, 'kr 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(88, 88, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(89, 89, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(90, 90, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(91, 91, 54, 'Q 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(92, 92, 49, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(93, 93, 53, 'FG 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(94, 94, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(95, 95, 55, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(96, 96, 59, 'G 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(97, 97, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(98, 98, 57, 'L 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(99, 99, 56, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(100, 100, 60, 'Ft 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(101, 101, 66, 'kr 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(102, 102, 63, '₹1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(103, 103, 61, 'Rp 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(104, 104, 65, 'ریال1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(105, 105, 64, 'ع.د1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(106, 106, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(107, 107, 47, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(108, 108, 62, '₪1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(109, 109, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(110, 110, 67, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(111, 111, 69, '¥1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(112, 112, 47, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(113, 113, 68, 'د.ا1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(114, 114, 78, '₸1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(115, 115, 70, 'KSh 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(116, 116, 8, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(117, 117, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(118, 118, 76, 'د.ك1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(119, 119, 71, 'с 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(120, 120, 79, '₭1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(121, 121, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(122, 122, 80, 'ل.ل1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(123, 123, 83, 'M 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(124, 124, 82, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(125, 125, 84, 'د.ل1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(126, 126, 28, 'Fr.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(127, 127, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(128, 128, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(129, 129, 91, 'P 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(130, 130, 87, 'Ar 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(131, 131, 95, 'K 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(132, 132, 97, 'RM 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(133, 133, 94, 'Rf 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(134, 134, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(135, 135, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(136, 136, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(137, 137, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(138, 138, 92, 'UM 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(139, 139, 93, '₨1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(140, 140, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(141, 141, 96, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(142, 142, 86, 'L 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(143, 143, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(144, 144, 90, '₮1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(145, 145, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(146, 146, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(147, 147, 85, 'د.م.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(148, 148, 98, 'MT 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(149, 149, 89, 'Ks 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(150, 150, 99, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(151, 151, 8, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(152, 152, 103, '₨1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(153, 153, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(154, 154, 152, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(155, 155, 104, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(156, 156, 101, 'C$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(157, 157, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(158, 158, 100, '₦1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(159, 159, 104, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(160, 160, 8, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(161, 161, 74, '₩1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(162, 162, 88, 'ден 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(163, 163, 47, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(164, 164, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(165, 165, 102, 'kr 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(166, 166, 105, 'ر.ع.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(167, 167, 110, '₨1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(168, 168, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(169, 169, 106, 'B/.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(170, 170, 108, 'K 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(171, 171, 112, '₲1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(172, 172, 107, 'S/1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(173, 173, 109, '₱1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(174, 174, 104, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(175, 175, 111, 'zł 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(176, 176, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(177, 177, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(178, 178, 113, 'ر.ق.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(179, 179, 149, 'FCFA 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(180, 180, 114, 'lei 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(181, 181, 116, '₽1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(182, 182, 117, 'FRw 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(183, 183, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(184, 184, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(185, 185, 124, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(186, 186, 124, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(187, 187, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(188, 188, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(189, 189, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(190, 190, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(191, 191, 150, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(192, 192, 148, 'T 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(193, 193, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(194, 194, 129, 'Db 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(195, 195, 118, 'ر.س1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(196, 196, 47, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(197, 197, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(198, 198, 115, 'дин.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(199, 199, 120, '₨1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(200, 200, 125, 'Le 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(201, 201, 123, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(202, 202, 5, 'ƒ1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(203, 203, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(204, 204, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(205, 205, 119, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(206, 206, 126, 'Sh 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(207, 207, 154, 'R 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(208, 208, 75, '₩1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(209, 209, 128, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(210, 210, 44, '€1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(211, 211, 81, 'රු1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(212, 212, 62, '₪1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(213, 213, 121, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(214, 214, 127, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(215, 215, 122, 'kr 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(216, 216, 28, 'Fr.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(217, 217, 131, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(218, 218, 138, 'NT$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(219, 219, 132, 'SM 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(220, 220, 139, 'Sh 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(221, 221, 157, '฿1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(222, 222, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(223, 223, 151, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(224, 224, 104, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(225, 225, 135, 'T$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(226, 226, 137, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(227, 227, 134, 'د.ت1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(228, 228, 133, 'm 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(229, 229, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(230, 230, 8, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(231, 231, 136, '₺1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(232, 232, 141, 'Sh 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(233, 233, 140, '₴1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(234, 234, 2, 'د.إ1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(235, 235, 47, '£1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(236, 236, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(237, 237, 143, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(238, 238, 144, 'сум 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(239, 239, 147, 'Vt 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(240, 240, 145, 'Bs.1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(241, 241, 146, '₫1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(242, 242, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(243, 243, 142, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(244, 244, 152, '₣1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(245, 245, 153, '﷼1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(246, 246, 155, 'K 1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL),
(247, 247, 156, '$1,234.56', '2025-08-21 13:19:48', '2025-08-21 13:19:48', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_countries_has_languages`
--

CREATE TABLE `geo_countries_has_languages` (
  `id` int NOT NULL COMMENT 'Unique identifier for each country/language relationship.',
  `id_country` int NOT NULL COMMENT 'Country ID.',
  `id_language` int NOT NULL COMMENT 'Language ID.',
  `principal` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicate whether it is the main language of the country.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship between countries and languages.';

--
-- Volcado de datos para la tabla `geo_countries_has_languages`
--

INSERT INTO `geo_countries_has_languages` (`id`, `id_country`, `id_language`, `principal`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, 123, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(2, 1, 31, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(3, 2, 2, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(4, 3, 4, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(5, 3, 13, 0, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(6, 4, 136, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(7, 4, 37, 0, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(8, 5, 20, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(9, 6, 127, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(10, 7, 37, 1, '2025-01-20 23:24:44', '2025-01-20 23:24:44', NULL),
(11, 8, 114, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(12, 9, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(13, 10, 154, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(14, 11, 5, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(15, 12, 35, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(16, 12, 122, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(17, 13, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(18, 14, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(19, 15, 50, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(20, 16, 7, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(21, 17, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(22, 18, 4, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(23, 19, 12, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(24, 20, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(25, 21, 10, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(26, 21, 135, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(27, 22, 35, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(28, 22, 44, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(29, 22, 50, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(30, 23, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(31, 23, 154, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(32, 24, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(33, 25, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(34, 26, 36, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(35, 27, 154, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(36, 27, 132, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(37, 27, 6, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(38, 28, 35, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(39, 29, 16, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(40, 29, 28, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(41, 29, 140, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(42, 30, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(43, 30, 143, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(44, 31, 127, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(45, 32, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(46, 33, 98, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(47, 34, 17, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(48, 35, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(49, 36, 81, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(50, 36, 44, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(51, 36, 37, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(52, 37, 127, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(53, 37, 19, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(54, 38, 77, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(55, 39, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(56, 39, 37, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(57, 40, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(58, 40, 44, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(59, 41, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(60, 42, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(61, 42, 137, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(62, 43, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(63, 43, 4, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(64, 44, 154, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(65, 45, 23, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(66, 46, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(67, 47, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(68, 48, 154, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(69, 49, 25, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(70, 49, 4, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(71, 49, 44, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(72, 50, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(73, 50, 26, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(74, 51, 154, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(75, 52, 28, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(76, 53, 154, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(77, 54, 35, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(78, 54, 122, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(79, 54, 37, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(80, 55, 52, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(81, 55, 172, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(82, 56, 29, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(83, 57, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(84, 57, 34, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(85, 58, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(86, 58, 92, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(87, 58, 79, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(88, 58, 156, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(89, 58, 171, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(90, 59, 30, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(91, 60, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(92, 61, 44, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(93, 61, 4, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(94, 62, 37, 1, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(95, 62, 86, 0, '2025-01-20 23:24:45', '2025-01-20 23:24:45', NULL),
(96, 63, 154, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(97, 64, 154, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(98, 64, 132, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(99, 65, 4, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(100, 66, 154, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(101, 67, 154, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(102, 67, 44, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(103, 67, 127, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(104, 68, 167, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(105, 68, 4, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(106, 68, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(107, 69, 38, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(108, 70, 157, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(109, 70, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(110, 71, 3, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(111, 71, 119, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(112, 71, 167, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(113, 71, 152, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(114, 72, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(115, 73, 40, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(116, 73, 30, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(117, 74, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(118, 75, 41, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(119, 75, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(120, 75, 60, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(121, 76, 43, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(122, 76, 158, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(123, 77, 44, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(124, 78, 35, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(125, 79, 44, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(126, 79, 159, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(127, 80, 44, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(128, 81, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(129, 82, 49, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(130, 83, 50, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(131, 84, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(132, 85, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(133, 86, 52, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(134, 87, 53, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(135, 87, 30, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(136, 88, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(137, 89, 44, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(138, 90, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(139, 90, 21, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(140, 91, 154, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(141, 91, 73, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(142, 91, 131, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(143, 92, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(144, 93, 44, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(145, 94, 127, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(146, 94, 27, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(147, 95, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(148, 96, 45, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(149, 96, 44, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(150, 97, 67, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(151, 97, 89, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(152, 97, 44, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(153, 98, 154, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(154, 99, 24, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(155, 99, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(156, 100, 62, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(157, 101, 63, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(158, 102, 59, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(159, 102, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(160, 102, 12, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(161, 102, 162, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(162, 102, 103, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(163, 102, 161, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(164, 102, 176, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(165, 103, 65, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(166, 104, 124, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(167, 105, 4, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(168, 105, 85, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(169, 106, 66, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(170, 106, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(171, 107, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(172, 107, 102, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(173, 108, 57, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(174, 108, 4, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(175, 109, 67, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(176, 110, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(177, 110, 68, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(178, 111, 69, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(179, 112, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(180, 112, 72, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(181, 113, 4, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(182, 114, 76, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(183, 114, 135, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(184, 115, 156, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(185, 115, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(186, 116, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(187, 116, 51, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(188, 117, 2, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(189, 117, 140, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(190, 118, 4, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(191, 119, 87, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(192, 119, 135, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(193, 120, 88, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(194, 121, 90, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(195, 122, 4, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(196, 122, 44, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(197, 122, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(198, 123, 142, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(199, 123, 37, 0, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(200, 124, 37, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(201, 125, 4, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(202, 126, 50, 1, '2025-01-20 23:24:46', '2025-01-20 23:24:46', NULL),
(203, 127, 93, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(204, 128, 94, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(205, 128, 44, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(206, 128, 50, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(207, 129, 24, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(208, 129, 127, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(209, 130, 97, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(210, 130, 44, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(211, 131, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(212, 131, 22, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(213, 132, 98, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(214, 132, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(215, 133, 32, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(216, 134, 8, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(217, 134, 44, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(218, 135, 99, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(219, 135, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(220, 136, 104, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(221, 136, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(222, 137, 44, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(223, 138, 4, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(224, 138, 44, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(225, 139, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(226, 139, 44, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(227, 139, 105, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(228, 140, 44, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(229, 141, 154, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(230, 142, 133, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(231, 142, 135, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(232, 143, 44, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(233, 144, 107, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(234, 145, 108, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(235, 145, 140, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(236, 146, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(237, 147, 4, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(238, 147, 13, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(239, 148, 127, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(240, 149, 18, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(241, 150, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(242, 150, 1, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(243, 150, 120, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(244, 150, 78, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(245, 150, 58, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(246, 151, 110, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(247, 151, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(248, 152, 111, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(249, 152, 96, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(250, 152, 14, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(251, 152, 166, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(252, 153, 35, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(253, 153, 46, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(254, 154, 44, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(255, 154, 75, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(256, 155, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(257, 155, 109, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(258, 155, 112, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(259, 156, 154, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(260, 157, 44, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(261, 157, 56, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(262, 157, 183, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(263, 158, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(264, 158, 56, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(265, 158, 182, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(266, 158, 64, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(267, 159, 113, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(268, 159, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(269, 160, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(270, 160, 115, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(271, 161, 83, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(272, 162, 95, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(273, 163, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(274, 163, 66, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(275, 164, 37, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(276, 164, 21, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(277, 165, 116, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(278, 166, 4, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(279, 167, 176, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(280, 167, 123, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(281, 167, 130, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(282, 167, 147, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(283, 168, 121, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(284, 168, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(285, 169, 154, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(286, 170, 168, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(287, 170, 61, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(288, 170, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(289, 171, 154, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(290, 171, 54, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(291, 172, 154, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(292, 172, 132, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(293, 172, 6, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(294, 173, 42, 1, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(295, 173, 37, 0, '2025-01-20 23:24:47', '2025-01-20 23:24:47', NULL),
(296, 174, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(297, 174, 125, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(298, 175, 126, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(299, 176, 127, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(300, 177, 154, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(301, 177, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(302, 178, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(303, 179, 44, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(304, 179, 92, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(305, 179, 82, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(306, 180, 133, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(307, 181, 135, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(308, 182, 80, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(309, 182, 44, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(310, 182, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(311, 183, 44, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(312, 184, 44, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(313, 185, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(314, 186, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(315, 187, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(316, 188, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(317, 189, 44, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(318, 190, 44, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(319, 191, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(320, 192, 136, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(321, 192, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(322, 193, 67, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(323, 194, 127, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(324, 195, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(325, 196, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(326, 196, 138, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(327, 196, 139, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(328, 197, 44, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(329, 197, 180, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(330, 197, 129, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(331, 197, 71, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(332, 197, 101, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(333, 198, 140, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(334, 198, 62, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(335, 198, 149, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(336, 198, 28, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(337, 199, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(338, 199, 44, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(339, 199, 144, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(340, 200, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(341, 200, 163, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(342, 200, 106, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(343, 200, 84, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(344, 200, 91, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(345, 201, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(346, 201, 100, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(347, 201, 98, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(348, 201, 161, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(349, 202, 35, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(350, 202, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(351, 203, 149, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(352, 203, 62, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(353, 203, 29, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(354, 204, 150, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(355, 204, 141, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(356, 205, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(357, 205, 151, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(358, 206, 152, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(359, 206, 4, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(360, 206, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(361, 207, 1, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(362, 207, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(363, 207, 184, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(364, 207, 181, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(365, 207, 153, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(366, 208, 83, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(367, 209, 4, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(368, 209, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(369, 209, 33, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(370, 209, 117, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(371, 210, 154, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(372, 210, 20, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(373, 210, 48, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(374, 210, 9, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(375, 211, 148, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(376, 211, 161, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(377, 212, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(378, 213, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(379, 213, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(380, 214, 35, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(381, 214, 155, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(382, 214, 59, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(383, 214, 70, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(384, 215, 158, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(385, 216, 50, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(386, 216, 44, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(387, 216, 67, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(388, 216, 134, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(389, 217, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(390, 218, 100, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(391, 219, 160, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(392, 219, 135, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(393, 220, 156, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(394, 220, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(395, 221, 165, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(396, 222, 164, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(397, 222, 127, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(398, 223, 44, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(399, 223, 39, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(400, 223, 74, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(401, 224, 169, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(402, 224, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(403, 225, 170, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(404, 225, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(405, 226, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(406, 226, 154, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(407, 226, 59, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(408, 227, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(409, 227, 44, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(410, 228, 173, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(411, 228, 135, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(412, 229, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(413, 230, 174, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(414, 230, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(415, 231, 172, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(416, 232, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(417, 232, 156, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(418, 233, 175, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(419, 233, 135, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(420, 234, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(421, 234, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(422, 235, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(423, 236, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(424, 237, 154, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(425, 238, 177, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(426, 238, 135, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(427, 239, 15, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(428, 239, 37, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(429, 239, 44, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(430, 240, 154, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(431, 241, 178, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(432, 242, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(433, 243, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(434, 244, 179, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(435, 244, 47, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(436, 244, 44, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(437, 245, 4, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(438, 246, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(439, 246, 11, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(440, 246, 118, 0, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(441, 247, 37, 1, '2025-01-20 23:24:48', '2025-01-20 23:24:48', NULL),
(442, 247, 145, 0, '2025-01-20 23:24:49', '2025-01-20 23:24:49', NULL),
(443, 247, 146, 0, '2025-01-20 23:24:49', '2025-01-20 23:24:49', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_dial_codes`
--

CREATE TABLE `geo_dial_codes` (
  `id` int NOT NULL COMMENT 'Unique identifier for each dialing code.',
  `id_country` int NOT NULL COMMENT 'Country ID to which the dialing code belongs.',
  `code` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Dialing code.',
  `mask` varchar(50) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Mask for each number that uses the dialing code.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Dialing codes for each country.';

--
-- Volcado de datos para la tabla `geo_dial_codes`
--

INSERT INTO `geo_dial_codes` (`id`, `id_country`, `code`, `mask`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, '+93', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(2, 2, '+355', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(3, 3, '+213', '(DC) ### ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(4, 4, '+1-684', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(5, 5, '+376', '(DC) ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(6, 6, '+244', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(7, 7, '+1-264', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(8, 9, '+1-268', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(9, 10, '+54', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(10, 11, '+374', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(11, 12, '+297', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(12, 13, '+247', '(DC) ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(13, 14, '+61', '(DC) # #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(14, 15, '+43', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(15, 16, '+994', '(DC) ## ### ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(16, 17, '+1-242', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(17, 18, '+973', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(18, 19, '+880', '(DC) #### ######', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(19, 20, '+1-246', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(20, 21, '+375', '(DC) ## ### ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(21, 22, '+32', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(22, 23, '+501', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(23, 24, '+229', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(24, 25, '+1-441', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(25, 26, '+975', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(26, 27, '+591', '(DC) # ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(27, 28, '+599', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(28, 29, '+387', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(29, 30, '+267', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(30, 31, '+55', '(DC) ## ##### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(31, 32, '+246', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(32, 33, '+673', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(33, 34, '+359', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(34, 35, '+226', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(35, 36, '+257', '(DC) ## ## ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(36, 37, '+238', '(DC) ### ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(37, 38, '+855', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(38, 39, '+237', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(39, 40, '+1', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(40, 41, '+1-345', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(41, 42, '+236', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(42, 43, '+235', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(43, 44, '+56', '(DC) # #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(44, 45, '+86', '(DC) #### #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(45, 46, '+61', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(46, 47, '+61', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(47, 48, '+57', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(48, 49, '+269', '(DC) ## ## ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(49, 50, '+682', '(DC) ## ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(50, 51, '+506', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(51, 52, '+385', '(DC) ## ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(52, 53, '+53', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(53, 54, '+599', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(54, 55, '+357', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(55, 56, '+420', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(56, 57, '+225', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(57, 58, '+243', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(58, 59, '+45', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(59, 60, '+246', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(60, 61, '+253', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(61, 62, '+1-767', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(62, 63, '+1-809', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(63, 63, '+1-829', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(64, 63, '+1-849', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(65, 64, '+593', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(66, 65, '+20', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(67, 66, '+503', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(68, 67, '+240', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(69, 68, '+291', '(DC) # ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(70, 69, '+372', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(71, 70, '+268', '(DC) ## ## ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(72, 71, '+251', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(73, 72, '+500', '(DC) #####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(74, 73, '+298', '(DC) ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(75, 74, '+691', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(76, 75, '+679', '(DC) ## ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(77, 76, '+358', '(DC) ## ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(78, 77, '+33', '(DC) # ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(79, 78, '+594', '(DC) ### ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(80, 79, '+689', '(DC) ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(81, 80, '+241', '(DC) # ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(82, 81, '+220', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(83, 82, '+995', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(84, 83, '+49', '(DC) ### #######', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(85, 84, '+233', '(DC) ## ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(86, 85, '+350', '(DC) ### #####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(87, 86, '+30', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(88, 87, '+299', '(DC) ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(89, 88, '+1-473', '(DC) ###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(90, 89, '+590', '(DC) ###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(91, 90, '+1-671', '(DC) ###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(92, 91, '+502', '(DC) ####-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(93, 92, '+44-1481', '(DC) ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(94, 93, '+224', '(DC) ###-##-##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(95, 94, '+245', '(DC) ###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(96, 95, '+592', '(DC) ###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(97, 96, '+509', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(98, 98, '+504', '(DC) ####-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(99, 99, '+852', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(100, 100, '+36', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(101, 101, '+354', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(102, 102, '+91', '(DC) #####-#####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(103, 103, '+62', '(DC) ###-###-###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(104, 104, '+98', '(DC) ###-###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(105, 105, '+964', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(106, 106, '+353', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(107, 107, '+44-1624', '(DC) ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(108, 108, '+972', '(DC) #-###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(109, 109, '+39', '(DC) #### #######', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(110, 110, '+1-876', '(DC) ###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(111, 111, '+81', '(DC) ####-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(112, 112, '+44-1534', '(DC) ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(113, 113, '+962', '(DC) # #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(114, 114, '+7', '(DC) ### ### ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(115, 115, '+254', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(116, 116, '+686', '(DC) ######', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(117, 117, '+383', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(118, 118, '+965', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(119, 119, '+996', '(DC) ### ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(120, 120, '+856', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(121, 121, '+371', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(122, 122, '+961', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(123, 123, '+266', '(DC) # #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(124, 124, '+231', '(DC) ## ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(125, 125, '+218', '(DC) ## ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(126, 126, '+423', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(127, 127, '+370', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(128, 128, '+352', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(129, 129, '+853', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(130, 130, '+261', '(DC) ## ## #####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(131, 131, '+265', '(DC) 1 ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(132, 132, '+60', '(DC) ###-#######', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(133, 133, '+960', '(DC) ###-####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(134, 134, '+223', '(DC) ## ## ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(135, 135, '+356', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(136, 136, '+692', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(137, 137, '+596', '(DC) ### ## ##', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(138, 138, '+222', '(DC) ## ## ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(139, 139, '+230', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(140, 140, '+262', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(141, 141, '+52', '(DC) ### ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(142, 142, '+373', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(143, 143, '+377', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(144, 144, '+976', '(DC) #### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(145, 145, '+382', '(DC) ## ### ###', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(146, 146, '+1 664', '(DC) ### ####', '2025-01-20 20:53:17', '2025-01-20 20:53:17', NULL),
(147, 147, '+212', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(148, 148, '+258', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(149, 149, '+95', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(150, 150, '+264', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(151, 151, '+674', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(152, 152, '+977', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(153, 153, '+31', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(154, 154, '+687', '(DC) ## ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(155, 155, '+64', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(156, 156, '+505', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(157, 157, '+227', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(158, 158, '+234', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(159, 159, '+683', '(DC) ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(160, 160, '+672', '(DC) ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(161, 161, '+850', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(162, 162, '+389', '(DC) ## ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(163, 164, '+1 670', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(164, 165, '+47', '(DC) ### ## ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(165, 166, '+968', '(DC) ### ######', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(166, 167, '+92', '(DC) ### #######', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(167, 168, '+680', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(168, 169, '+507', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(169, 170, '+675', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(170, 171, '+595', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(171, 172, '+51', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(172, 173, '+63', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(173, 174, '+64', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(174, 175, '+48', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(175, 176, '+351', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(176, 177, '+1 787', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(177, 177, '+1 939', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(178, 178, '+974', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(179, 179, '+242', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(180, 180, '+40', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(181, 181, '+7', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(182, 182, '+250', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(183, 183, '+262', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(184, 184, '+590', '(DC) ### ## ##', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(185, 185, '+290', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(186, 186, '+290', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(187, 186, '+247', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(188, 187, '+1869', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(189, 188, '+1758', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(190, 189, '+590', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(191, 190, '+508', '(DC) ## ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(192, 191, '+1784', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(193, 192, '+685', '(DC) ## ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(194, 193, '+378', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(195, 194, '+239', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(196, 195, '+966', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(197, 197, '+221', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(198, 198, '+381', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(199, 199, '+248', '(DC) # ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(200, 200, '+232', '(DC) ## ######', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(201, 201, '+65', '(DC) #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(202, 202, '+1721', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(203, 203, '+421', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(204, 204, '+386', '(DC) ## ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(205, 205, '+677', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(206, 206, '+252', '(DC) # ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(207, 207, '+27', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(208, 208, '+82', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(209, 209, '+211', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(210, 210, '+34', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(211, 211, '+94', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(212, 212, '+970', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(213, 213, '+249', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(214, 214, '+597', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(215, 215, '+46', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(216, 216, '+41', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(217, 217, '+963', '(DC) ## #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(218, 218, '+886', '(DC) ## #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(219, 219, '+992', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(220, 220, '+255', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(221, 221, '+66', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(222, 222, '+670', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(223, 223, '+228', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(224, 224, '+690', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(225, 225, '+676', '(DC) #####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(226, 226, '+1868', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(227, 227, '+216', '(DC) ## ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(228, 228, '+993', '(DC) ## ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(229, 229, '+1649', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(230, 230, '+688', '(DC) ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(231, 231, '+90', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(232, 232, '+256', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(233, 233, '+380', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(234, 234, '+971', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(235, 235, '+44', '(DC) #### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(236, 236, '+1', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(237, 237, '+598', '(DC) # ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(238, 238, '+998', '(DC) ## ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(239, 239, '+678', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(240, 240, '+58', '(DC) ### ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(241, 241, '+84', '(DC) ## #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(242, 242, '+1284', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(243, 243, '+1340', '(DC) ### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(244, 244, '+681', '(DC) ## ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(245, 245, '+967', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(246, 246, '+260', '(DC) ### ### ###', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL),
(247, 247, '+263', '(DC) # #### ####', '2025-01-20 20:53:18', '2025-01-20 20:53:18', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_regions`
--

CREATE TABLE `geo_regions` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each region.',
  `id_continent` int NOT NULL COMMENT 'ID of the continent to which the region belongs.',
  `name` json NOT NULL COMMENT 'Name of the region, written in different languages for internationalization.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the regions of the continents.';

--
-- Volcado de datos para la tabla `geo_regions`
--

INSERT INTO `geo_regions` (`id`, `id_continent`, `name`) VALUES
(1, 1, '{\"en\": \"Southern Africa\"}'),
(2, 1, '{\"en\": \"Middle Africa\"}'),
(3, 1, '{\"en\": \"Northern Africa\"}'),
(4, 1, '{\"en\": \"Western Africa\"}'),
(5, 1, '{\"en\": \"Eastern Africa\"}'),
(6, 2, '{\"en\": \"South America\"}'),
(7, 2, '{\"en\": \"Caribbean\"}'),
(8, 2, '{\"en\": \"North America\"}'),
(9, 2, '{\"en\": \"Central America\"}'),
(10, 3, '{\"en\": \"Antarctic\"}'),
(11, 4, '{\"en\": \"Eastern Asia\"}'),
(12, 4, '{\"en\": \"Western Asia\"}'),
(13, 4, '{\"en\": \"Southern Asia\"}'),
(14, 4, '{\"en\": \"South-Eastern Asia\"}'),
(15, 4, '{\"en\": \"Central Asia\"}'),
(16, 5, '{\"en\": \"Northern Europe\"}'),
(17, 5, '{\"en\": \"Southern Europe\"}'),
(18, 5, '{\"en\": \"Western Europe\"}'),
(19, 5, '{\"en\": \"Southeast Europe\"}'),
(20, 5, '{\"en\": \"Central Europe\"}'),
(21, 5, '{\"en\": \"Eastern Europe\"}'),
(22, 6, '{\"en\": \"Melanesia\"}'),
(23, 6, '{\"en\": \"Micronesia\"}'),
(24, 6, '{\"en\": \"Polynesia\"}'),
(25, 6, '{\"en\": \"Australia and New Zealand\"}');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `geo_sub_divisions`
--

CREATE TABLE `geo_sub_divisions` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each political subdivision.',
  `id_country` int NOT NULL COMMENT 'ID of the country to which the subdivision belongs.',
  `id_capital` int DEFAULT NULL COMMENT 'ID of the capital city of the subdivision.',
  `name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Original name of the subdivision.',
  `denomination` enum('state','department','province','county','district','parish') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Definition of the type of subdivision (department, state, or province).'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the political subdivisions of a country.';

--
-- Volcado de datos para la tabla `geo_sub_divisions`
--

INSERT INTO `geo_sub_divisions` (`id`, `id_country`, `id_capital`, `name`, `denomination`) VALUES
(1, 1, NULL, 'Badahšan', 'province'),
(2, 1, NULL, 'Bādgīs', 'province'),
(3, 1, NULL, 'Baġlān', 'province'),
(4, 1, NULL, 'Balh', 'province'),
(5, 1, NULL, 'Bāmiyān', 'province'),
(6, 1, NULL, 'Daikondi', 'province'),
(7, 1, NULL, 'Farāh', 'province'),
(8, 1, NULL, 'Fāryāb', 'province'),
(9, 1, NULL, 'Ġaznī', 'province'),
(10, 1, NULL, 'Ġawr', 'province'),
(11, 1, NULL, 'Helmand', 'province'),
(12, 1, NULL, 'Herāt', 'province'),
(13, 1, NULL, 'Jawzjān', 'province'),
(14, 1, NULL, 'Kabul', 'province'),
(15, 1, NULL, 'Kandahar', 'province'),
(16, 1, NULL, 'Kāpīsā', 'province'),
(17, 1, NULL, 'Jost', 'province'),
(18, 1, NULL, 'Kunar', 'province'),
(19, 1, NULL, 'Qundūz', 'province'),
(20, 1, NULL, 'Laġmān', 'province'),
(21, 1, NULL, 'Lawgar', 'province'),
(22, 1, NULL, 'Nangarhār', 'province'),
(23, 1, NULL, 'Nimruz', 'province'),
(24, 1, NULL, 'Nūristān', 'province'),
(25, 1, NULL, 'Urūzgān', 'province'),
(26, 1, NULL, 'Paktiyā', 'province'),
(27, 1, NULL, 'Paktīkā', 'province'),
(28, 1, NULL, 'Panjshīr', 'province'),
(29, 1, NULL, 'Parwān', 'province'),
(30, 1, NULL, 'Samangān', 'province'),
(31, 1, NULL, 'Sar-e', 'province'),
(32, 1, NULL, 'Tahār', 'province'),
(33, 1, NULL, 'Vardak', 'province'),
(34, 1, NULL, 'Zābul', 'province'),
(35, 2, NULL, 'Berat', 'county'),
(36, 2, NULL, 'Dibër', 'county'),
(37, 2, NULL, 'Durrës', 'county'),
(38, 2, NULL, 'Elbasan', 'county'),
(39, 2, NULL, 'Fier', 'county'),
(40, 2, NULL, 'Gjirokastër', 'county'),
(41, 2, NULL, 'Korçë', 'county'),
(42, 2, NULL, 'Kukës', 'county'),
(43, 2, NULL, 'Lezhë', 'county'),
(44, 2, NULL, 'Shkodër', 'county'),
(45, 2, NULL, 'Tiranë', 'county'),
(46, 2, NULL, 'Vlorë', 'county'),
(47, 3, NULL, 'Valiato', 'county'),
(48, 3, NULL, '#', 'county'),
(49, 3, NULL, 'Adrar', 'county'),
(50, 3, NULL, '30', 'county'),
(51, 3, NULL, 'Chlef', 'county'),
(52, 3, NULL, 'Orán', 'county'),
(53, 3, NULL, 'Laghouat', 'county'),
(54, 3, NULL, 'El Bayadh', 'county'),
(55, 3, NULL, 'Oum El Bouaghi', 'county'),
(56, 3, NULL, 'Illizi', 'county'),
(57, 3, NULL, 'Batna', 'county'),
(58, 3, NULL, 'Bordj Bou Arréridj', 'county'),
(59, 3, NULL, 'Bugía', 'county'),
(60, 3, NULL, 'Bumerdés', 'county'),
(61, 3, NULL, 'Biskra', 'county'),
(62, 3, NULL, 'El Tarf', 'county'),
(63, 3, NULL, 'Béchar', 'county'),
(64, 3, NULL, 'Tinduf', 'county'),
(65, 3, NULL, 'Blida', 'county'),
(66, 3, NULL, 'Tissemsilt', 'county'),
(67, 3, NULL, 'Bouira', 'county'),
(68, 3, NULL, 'El Oued', 'county'),
(69, 3, NULL, 'Tamanrasset', 'county'),
(70, 3, NULL, 'Jenchela', 'county'),
(71, 3, NULL, 'Tébessa', 'county'),
(72, 3, NULL, 'Souk Ahras', 'county'),
(73, 3, NULL, 'Tremecén', 'county'),
(74, 3, NULL, 'Tipasa', 'county'),
(75, 3, NULL, 'Tiaret', 'county'),
(76, 3, NULL, 'Mila', 'county'),
(77, 3, NULL, 'Tizi Uzu', 'county'),
(78, 3, NULL, 'Aín Defla', 'county'),
(79, 3, NULL, 'Argel', 'county'),
(80, 3, NULL, 'Naama', 'county'),
(81, 3, NULL, 'Djelfa', 'county'),
(82, 3, NULL, 'Aín Temushent', 'county'),
(83, 3, NULL, 'Jijel', 'county'),
(84, 3, NULL, 'Gardaya', 'county'),
(85, 3, NULL, 'Sétif', 'county'),
(86, 3, NULL, 'Relizan', 'county'),
(87, 3, NULL, 'Saida', 'county'),
(88, 3, NULL, 'El M\'Ghair', 'county'),
(89, 3, NULL, 'Skikda', 'county'),
(90, 3, NULL, 'El Menia', 'county'),
(91, 3, NULL, 'Sidi Bel Abbes', 'county'),
(92, 3, NULL, 'Ouled Djellal', 'county'),
(93, 3, NULL, 'Annaba', 'county'),
(94, 3, NULL, 'Bordj Badji Mokhtar', 'county'),
(95, 3, NULL, 'Guelma', 'county'),
(96, 3, NULL, 'Béni Abbès', 'county'),
(97, 3, NULL, 'Constantina', 'county'),
(98, 3, NULL, 'Timimoun', 'county'),
(99, 3, NULL, 'Médéa', 'county'),
(100, 3, NULL, 'Touggourt', 'county'),
(101, 3, NULL, 'Mostaganem', 'county'),
(102, 3, NULL, 'Djanet', 'county'),
(103, 3, NULL, 'M\'Sila', 'county'),
(104, 3, NULL, 'In Salah', 'county'),
(105, 3, NULL, 'Muaskar', 'county'),
(106, 3, NULL, 'In Guezzam', 'county'),
(107, 4, NULL, 'Western', 'state'),
(108, 4, NULL, 'Eastern', 'state'),
(109, 4, NULL, 'Manuʻa', 'state'),
(117, 5, NULL, 'Canillo', 'parish'),
(118, 5, NULL, 'Encamp', 'parish'),
(119, 5, NULL, 'Ordino', 'parish'),
(120, 5, NULL, 'La Massana', 'parish'),
(121, 5, NULL, 'Andorra la Vieja', 'parish'),
(122, 5, NULL, 'San Julián de Loria', 'parish'),
(123, 5, NULL, 'Las Escaldas-Engordany', 'parish'),
(124, 6, NULL, 'Bengo', 'province'),
(125, 6, NULL, 'Benguela', 'province'),
(126, 6, NULL, 'Bié', 'province'),
(127, 6, NULL, 'Cabinda', 'province'),
(128, 6, NULL, 'Kuando Kubango', 'province'),
(129, 6, NULL, 'Kwanza-Norte', 'province'),
(130, 6, NULL, 'Kwanza-Sul', 'province'),
(131, 6, NULL, 'Cunene', 'province'),
(132, 6, NULL, 'Huambo', 'province'),
(133, 6, NULL, 'Huila', 'province'),
(134, 6, NULL, 'Luanda', 'province'),
(135, 6, NULL, 'Lunda-Norte', 'province'),
(136, 6, NULL, 'Lunda-Sul', 'province'),
(137, 6, NULL, 'Malanje', 'province'),
(138, 6, NULL, 'Moxico', 'province'),
(139, 6, NULL, 'Namibe', 'province'),
(140, 6, NULL, 'Uíge', 'province'),
(141, 6, NULL, 'Zaire', 'province');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `hr_contracts`
--

CREATE TABLE `hr_contracts` (
  `id` int NOT NULL COMMENT 'Unique identifier for each employment contract.',
  `id_employee` int NOT NULL COMMENT 'ID of the employee associated with this contract.',
  `id_branch` int NOT NULL COMMENT 'ID of the branch where the employee will work.',
  `id_contract_type` int NOT NULL COMMENT 'ID of the contract type (full-time, part-time, temporary, etc.).',
  `id_position` int NOT NULL COMMENT 'ID of the position/job role assigned to the employee.',
  `contract_number` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique contract number for identification and legal purposes.',
  `start_date` date NOT NULL COMMENT 'Date when the employment contract begins.',
  `end_date` date DEFAULT NULL COMMENT 'Date when the employment contract ends. NULL for indefinite contracts.',
  `salary` decimal(15,2) NOT NULL COMMENT 'Base salary amount agreed in the contract.',
  `currency` varchar(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'USD' COMMENT 'Currency code for the salary (ISO 4217 format).',
  `work_hours_per_week` int NOT NULL DEFAULT '40' COMMENT 'Number of working hours per week as per contract.',
  `probation_period_months` int DEFAULT NULL COMMENT 'Duration of probation period in months. NULL if no probation period.',
  `status` enum('draft','pending_signature','pending_start','active','suspended','expired','terminated','settled','rescinded','pending_settlement') COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'draft' COMMENT 'Contract states: draft (drafting), pending_signature (awaiting signatures), pending_start (signed but not active), active (in effect), suspended (paused), expired (reached end date), terminated (early end), settled (obligations fulfilled), rescinded (legally voided), pending_settlement (awaiting settlement); Flow: draft -> pending_signature -> pending_start -> active; active <-> suspended; active -> expired|terminated|rescinded; expired|terminated|rescinded -> pending_settlement -> settled',
  `signed_date` date DEFAULT NULL COMMENT 'Date when the contract was signed by both parties.',
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Additional notes or special conditions related to the contract.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Types of leave available to employees (vacation, sick, maternity, etc.).';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_categories`
--

CREATE TABLE `inv_categories` (
  `id` int NOT NULL COMMENT 'Unique category identifier.',
  `id_type` int NOT NULL COMMENT 'ID of each category type.',
  `name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Category name.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Category description.',
  `created_at` timestamp NOT NULL COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NOT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Classification of items or services.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_company_assets`
--

CREATE TABLE `inv_company_assets` (
  `id` int NOT NULL COMMENT 'Unique identifier for each asset.',
  `id_contract` int NOT NULL COMMENT 'Contract ID of the employee responsible for the asset.',
  `code` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique code for the asset.',
  `name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the asset (e.g., "Printer", "Forklift").',
  `acquisition_date` date NOT NULL COMMENT 'Date when the asset was acquired.',
  `depreciation_rate` decimal(5,2) DEFAULT NULL COMMENT 'Annual depreciation rate (%).',
  `current_value` decimal(12,2) NOT NULL COMMENT 'Current value after depreciation calculation.',
  `status` enum('delivered','in_warehouse') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Status (e.g., in use, in warehouse, maintenance).',
  `extra_info` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Additional information about the asset.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.	',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.	'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Company assets that are not for sale';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_contracts_has_assets`
--

CREATE TABLE `inv_contracts_has_assets` (
  `id` int NOT NULL COMMENT 'Unique identifier for each employee-asset relationship.',
  `id_contract` int NOT NULL COMMENT 'Contract ID of the employee who has in his/her possession, or who collaborates with the asset.',
  `id_asset` int NOT NULL COMMENT 'Asset ID assigned to the employee.',
  `type` enum('loan','collaborator') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Indicates what type of assignment the relationship is. If it is a loan, it indicates that the asset has been loaned to the employee for work use; while if it is a collaborator type, it indicates that the employee is responsible for maintaining, caring for, and using the asset under the supervision of the employee''s supervisor.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship of assets and employees.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_contracts_has_items`
--

CREATE TABLE `inv_contracts_has_items` (
  `id` int NOT NULL COMMENT 'Unique identifier for each relationship.',
  `id_contract` int NOT NULL COMMENT 'Supplier contract ID.',
  `id_item` int NOT NULL COMMENT 'ID of the item or service offered by the supplier.',
  `quantity` int NOT NULL DEFAULT '0' COMMENT 'Number of units that have been obtained by the supplier.',
  `measure` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Measurement of each item.',
  `amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT 'Amount of money spent obtaining items from this supplier.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Items offered to customers.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_details`
--

CREATE TABLE `inv_details` (
  `id` int NOT NULL COMMENT 'Unique identifier for the item or asset detail',
  `id_item` int DEFAULT NULL COMMENT 'ID of the item or service offered to the customer.',
  `id_asset` int DEFAULT NULL COMMENT 'Company asset ID.',
  `type` enum('components','ingredients','additional','information') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Type of detail (e.g., component, ingredient, etc.).',
  `name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the detail (e.g., "CPU", "Sugar", etc.).',
  `value` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Value of the detail (e.g., "Intel i7", "500g").',
  `quantity` decimal(10,2) NOT NULL COMMENT 'Quantity of the detail (e.g., "2 units", "500g").',
  `unit` enum('kg','g','unit','ml') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Unit of measurement (e.g., kg, g, unit, ml, etc.).',
  `is_mandatory` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates if the detail is mandatory	',
  `extra_info` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Additional information about the detail.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.	'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Details of each item or asset.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_inventories`
--

CREATE TABLE `inv_inventories` (
  `id` int NOT NULL COMMENT 'Unique identifier for each inventory.',
  `id_contract` int NOT NULL COMMENT 'Contract ID of the employee who performed the inventory.',
  `id_branch` int NOT NULL COMMENT 'ID of the location where the inventory is being carried out.',
  `id_warehouse` int DEFAULT NULL COMMENT 'ID of the warehouse where the item or asset is located. If null, it could indicate that it is being displayed for customers and not stored (in the case of items); or if it is an asset, that it is not a tangible item.',
  `start_date` date NOT NULL COMMENT 'Start date of the range in which the inventory is current.',
  `end_date` date NOT NULL COMMENT 'End date of the date range for which the inventory is valid.',
  `observations` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Special observations or notes that need to be considered when revisiting the inventory.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Inventory configuration.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_inventories_details`
--

CREATE TABLE `inv_inventories_details` (
  `id` int NOT NULL COMMENT 'Unique identifier for each item in an inventory.',
  `id_inventory` int NOT NULL COMMENT 'ID of the inventory configuration in which the details will be recorded.',
  `id_state` int NOT NULL DEFAULT '1' COMMENT 'Status ID for each item or asset in inventory.',
  `id_item` int DEFAULT NULL COMMENT 'ID of the item to be recorded in the inventory.',
  `id_asset` int DEFAULT NULL COMMENT 'ID of the asset to be recorded in the inventory.',
  `stock` int NOT NULL DEFAULT '1' COMMENT 'Current quantity of the item or asset recorded in inventory.',
  `min` int NOT NULL DEFAULT '1' COMMENT 'Minimum quantity of item that should always be kept at the headquarters.',
  `obervations` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Observations or details that should be considered for this detail.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Asset and item details of a configured inventory.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_inventories_states`
--

CREATE TABLE `inv_inventories_states` (
  `id` int NOT NULL COMMENT 'Unique identifier for each state.',
  `status` json NOT NULL COMMENT 'Status translated into several languages.',
  `description` json DEFAULT NULL COMMENT 'Description of what each status indicates regarding the inventories of each item or asset.',
  `type` enum('asset','item','both') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'both' COMMENT 'Indicates whether the status applies to assets, items, or both.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='States available for inventory detail.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_items`
--

CREATE TABLE `inv_items` (
  `id` int NOT NULL COMMENT 'Unique item identifier.',
  `id_category` int NOT NULL COMMENT 'Foreign key to item categories.',
  `name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Item name.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Item description.',
  `unit_price` decimal(10,2) NOT NULL COMMENT 'Unit price of the item/service',
  `unit_measurement` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unit of measurement (e.g., kg, pcs, hrs)',
  `tax_rate` decimal(5,2) NOT NULL COMMENT 'Applicable tax rate.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Items offered to the public.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_items_overrides`
--

CREATE TABLE `inv_items_overrides` (
  `id` int NOT NULL COMMENT 'Unique identifier for each overwrite.',
  `id_item` int NOT NULL COMMENT 'ID of the item to override the price.',
  `unit_price` decimal(10,2) NOT NULL COMMENT 'New unit price for each item.',
  `unit_measurement` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'New unit of measurement for supply.',
  `tax_rate` decimal(5,2) NOT NULL COMMENT 'Indicates whether taxes are due this time.',
  `start_date` date NOT NULL COMMENT 'Start date on which changes will be applied to the item.',
  `end_date` date DEFAULT NULL COMMENT 'Date on which changes to the item end. If void, it is considered a permanent change, or until further notice.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Discounts or other changes to a item.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_movements`
--

CREATE TABLE `inv_movements` (
  `id` int NOT NULL COMMENT 'Unique identifier for the movement.',
  `id_type` int NOT NULL COMMENT 'Movement type ID.',
  `id_item` int DEFAULT NULL COMMENT 'ID of the item to which the movement is linked.',
  `id_asset` int DEFAULT NULL COMMENT 'ID of the asset associated with the movement.',
  `id_warehouse` int DEFAULT NULL COMMENT 'ID of the warehouse where the item or asset is located.',
  `id_contract` int DEFAULT NULL COMMENT 'Contract ID associated with the movement.',
  `id_movement` int DEFAULT NULL COMMENT 'Movement ID associated with another movement.',
  `quantity` int NOT NULL COMMENT 'Quantity of items in the movement.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Additional details about the movement.',
  `status` enum('pending','process','done','waiting') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending' COMMENT 'Indicates the status of the movement. If it is ''waiting'', it indicates that an error occurred and is waiting to be resolved before it can be completed.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Record of internal movements of items and assets.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_movements_types`
--

CREATE TABLE `inv_movements_types` (
  `id` int NOT NULL COMMENT 'Unique identifier for each type of movement.',
  `type` json NOT NULL COMMENT 'Movement type in multiple languages.',
  `description` json DEFAULT NULL COMMENT 'Public description in multiple languages of the movement type.',
  `action` enum('addition','subtraction','both') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Indicate what action causes each type of movement.',
  `developer_information` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Relevant information for the platform developers, providing guidance on how to manage movements based on their type. This information should not be displayed to the end user.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Types of possible movements.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_types_categories`
--

CREATE TABLE `inv_types_categories` (
  `id` int NOT NULL COMMENT 'Unique type identifier.',
  `name` json NOT NULL COMMENT 'Category type name translated into multiple languages.',
  `description` json NOT NULL COMMENT 'Overview of categories belonging to this type translated into several languages.',
  `for_clients` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the type is for categories that are offered to the public, or are internal to the company.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.	',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.	'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Types to which the categories belong.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inv_warehouses`
--

CREATE TABLE `inv_warehouses` (
  `id` int NOT NULL COMMENT 'Unique warehouse identifier.',
  `name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Warehouse name.',
  `location` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Warehouse address or location.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.	',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.	'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Storage locations for items.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `logs_creation`
--

CREATE TABLE `logs_creation` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each creation log.',
  `responsible` json NOT NULL COMMENT 'Information about the user who created the record. This is stored as JSON in case the account and/or user is deleted.',
  `data` json NOT NULL COMMENT 'Information about the created record. It is stored as JSON in case the record is later deleted.',
  `table_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the table where the record was created.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created. This is more useful for debugging purposes than for information.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores creation logs for certain tables.';

--
-- Volcado de datos para la tabla `logs_creation`
--

INSERT INTO `logs_creation` (`id`, `responsible`, `data`, `table_name`, `created_at`) VALUES
(1, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 18, \"path\": \"/test\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:45:21.524Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-04T23:45:21.526Z\", \"description\": \"Test\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": false}', 'config_endpoints', '2025-05-04 23:45:21'),
(2, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 1, \"name\": \"index\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:52.936Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:52.939Z\", \"description\": \"First page of the application\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:05:52'),
(3, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 2, \"name\": \"login\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;login\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:52.979Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:52.979Z\", \"description\": \"Login page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:05:52'),
(4, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 3, \"name\": \"signup\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;signup\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:52.993Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:52.993Z\", \"description\": \"Signup page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:05:52'),
(5, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 4, \"name\": \"confirm-account\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;confirm-account\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:53.013Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:53.013Z\", \"description\": \"Confirm account page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:05:53'),
(6, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 5, \"name\": \"forgot-password\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;forgot-password\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:53.044Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:53.044Z\", \"description\": \"Forgot password page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:05:53'),
(7, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 6, \"name\": \"recover-password\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;recover-password\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:53.070Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:53.070Z\", \"description\": \"Recover password page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:05:53'),
(8, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 7, \"name\": \"endpoints\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;config&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;endpoints\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:53.086Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:53.086Z\", \"description\": \"RESTful API endpoint management.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:05:53'),
(9, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 8, \"name\": \"pages\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;config&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;pages\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:53.098Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:53.098Z\", \"description\": \"Managing pages of the current application.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:05:53'),
(10, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 9, \"name\": \"roles\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;config&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;roles\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:53.113Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:53.113Z\", \"description\": \"Application role management.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:05:53'),
(11, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 10, \"name\": \"taxes\", \"path\": \"http://localhost:5173&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;config&amp;amp;amp&amp;#x5C;;#x2F&amp;#x5C;;taxes\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:05:53.126Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:05:53.126Z\", \"description\": \"Managing tax information to always keep in mind.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:05:53'),
(12, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 1, \"name\": \"index\", \"path\": \"/\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.778Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.779Z\", \"description\": \"First page of the application\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:07:24'),
(13, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 2, \"name\": \"login\", \"path\": \"/login\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.813Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.813Z\", \"description\": \"Login page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:07:24'),
(14, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 3, \"name\": \"signup\", \"path\": \"/signup\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.842Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.842Z\", \"description\": \"Signup page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:07:24'),
(15, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 4, \"name\": \"confirm-account\", \"path\": \"/confirm-account\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.899Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.899Z\", \"description\": \"Confirm account page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:07:24'),
(16, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 5, \"name\": \"forgot-password\", \"path\": \"/forgot-password\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.945Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.945Z\", \"description\": \"Forgot password page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:07:24'),
(17, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 6, \"name\": \"recover-password\", \"path\": \"/recover-password\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.960Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.960Z\", \"description\": \"Recover password page\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', 'config_pages', '2025-05-30 00:07:24'),
(18, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 7, \"name\": \"endpoints\", \"path\": \"/config/endpoints\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.969Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.969Z\", \"description\": \"RESTful API endpoint management.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:07:24'),
(19, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 8, \"name\": \"pages\", \"path\": \"/config/pages\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.977Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.977Z\", \"description\": \"Managing pages of the current application.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:07:24'),
(20, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 9, \"name\": \"roles\", \"path\": \"/config/roles\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.987Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.987Z\", \"description\": \"Application role management.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:07:24'),
(21, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', '{\"id\": 10, \"name\": \"taxes\", \"path\": \"/config/taxes\", \"level\": 1, \"idPage\": null, \"createdAt\": \"2025-05-30T00:07:24.997Z\", \"deletedAt\": null, \"updatedAt\": \"2025-05-30T00:07:24.998Z\", \"description\": \"Managing tax information to always keep in mind.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', 'config_pages', '2025-05-30 00:07:24');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `logs_deletion`
--

CREATE TABLE `logs_deletion` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each deletion log.',
  `responsible` json NOT NULL COMMENT 'Information about the person who deleted the record. This is stored in JSON format in case the person responsible is also deleted.',
  `table_name` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the table from which the record was deleted.',
  `old_data` json NOT NULL COMMENT 'Data from the record that was deleted. In JSON format for easier reading.',
  `deleted_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Exact date and time when the record was deleted.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores information that has been deleted.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `logs_statuses`
--

CREATE TABLE `logs_statuses` (
  `id` int NOT NULL COMMENT 'Unique identifier for each log.',
  `responsible` json NOT NULL COMMENT 'Unique identifier for each record.',
  `table_name` varchar(200) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Table where the record is located.',
  `id_row` int NOT NULL COMMENT 'ID of the record whose status was changed.',
  `status` tinyint(1) NOT NULL COMMENT 'Registration enabled (1) or disabled (0).',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time the status was changed.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='State change log (soft delete).';

--
-- Volcado de datos para la tabla `logs_statuses`
--

INSERT INTO `logs_statuses` (`id`, `responsible`, `table_name`, `id_row`, `status`, `updated_at`) VALUES
(1, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', 9, 0, '2025-05-04 23:20:53'),
(2, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', 9, 1, '2025-05-04 23:20:59'),
(3, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', 17, 0, '2025-05-05 00:06:25'),
(4, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', 17, 1, '2025-05-05 00:06:27'),
(5, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', 3, 0, '2025-05-05 00:46:31'),
(6, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', 3, 1, '2025-05-05 00:46:33');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `logs_update`
--

CREATE TABLE `logs_update` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each update log.',
  `responsible` json NOT NULL COMMENT 'Data of the person responsible for updating the registry. In JSON format in case the user or account is subsequently deleted.',
  `table_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the table where the record was updated.',
  `old_data` json NOT NULL COMMENT 'Old information of the record in JSON format or similar.',
  `new_data` json NOT NULL COMMENT 'New updated information of the record in JSON format or similar.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was updated. This is more useful for debugging purposes than for information.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores important updated information.';

--
-- Volcado de datos para la tabla `logs_update`
--

INSERT INTO `logs_update` (`id`, `responsible`, `table_name`, `old_data`, `new_data`, `updated_at`) VALUES
(1, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 12, \"path\": \"/api/v1/config/endpoints\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 1, \"updatedAt\": \"2025-05-04T23:09:08.202Z\", \"description\": \"Register an endpoint manually in the database.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '{\"id\": 12, \"path\": \"/api/v1/config/endpoints\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 1, \"updatedAt\": \"2025-05-04T23:09:08.202Z\", \"description\": \"Register an endpoint manually in the database.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '2025-05-04 23:09:08'),
(2, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 13, \"path\": \"/api/v1/config/endpoints\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-04T23:09:53.878Z\", \"description\": \"List information about endpoints registered in the database.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '{\"id\": 13, \"path\": \"/api/v1/config/endpoints\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-04T23:09:53.878Z\", \"description\": \"List information about endpoints registered in the database.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '2025-05-04 23:09:53'),
(3, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 14, \"path\": \"/api/v1/config/endpoints\", \"method\": {\"original\": \"put\", \"translated\": \"enums.method.put\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 3, \"updatedAt\": \"2025-05-04T23:10:38.436Z\", \"description\": \"Update statuses (soft delete) of one or more endpoints.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '{\"id\": 14, \"path\": \"/api/v1/config/endpoints\", \"method\": {\"original\": \"put\", \"translated\": \"enums.method.put\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 3, \"updatedAt\": \"2025-05-04T23:10:38.436Z\", \"description\": \"Update statuses (soft delete) of one or more endpoints.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '2025-05-04 23:10:38'),
(4, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 15, \"path\": \"/api/v1/config/endpoints/:id\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-04T23:17:00.045Z\", \"description\": \"Get more details about a specific endpoint.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '{\"id\": 15, \"path\": \"/api/v1/config/endpoints/:id\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-04T23:17:00.045Z\", \"description\": \"Get more details about a specific endpoint.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '2025-05-04 23:17:00'),
(5, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 16, \"path\": \"/api/v1/config/endpoints/:id\", \"method\": {\"original\": \"patch\", \"translated\": \"enums.method.patch\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 4, \"updatedAt\": \"2025-05-04T23:17:35.017Z\", \"description\": \"Update basic information for a specific endpoint.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '{\"id\": 16, \"path\": \"/api/v1/config/endpoints/:id\", \"method\": {\"original\": \"patch\", \"translated\": \"enums.method.patch\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 4, \"updatedAt\": \"2025-05-04T23:17:35.017Z\", \"description\": \"Update basic information for a specific endpoint.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '2025-05-04 23:17:35'),
(6, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 17, \"path\": \"/api/v1/config/endpoints/:id\", \"method\": {\"original\": \"delete\", \"translated\": \"enums.method.delete\"}, \"createdAt\": \"2025-05-04T23:07:24.000Z\", \"deletedAt\": null, \"methodInt\": 5, \"updatedAt\": \"2025-05-04T23:18:14.225Z\", \"description\": null, \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '{\"id\": 17, \"path\": \"/api/v1/config/endpoints/:id\", \"method\": {\"original\": \"delete\", \"translated\": \"enums.method.delete\"}, \"createdAt\": \"2025-05-04T23:07:24.000Z\", \"deletedAt\": null, \"methodInt\": 5, \"updatedAt\": \"2025-05-04T23:18:14.225Z\", \"description\": \"Permanently delete a specific endpoint from the database.\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": true}', '2025-05-04 23:18:14'),
(7, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 11, \"path\": \"/api/v1/security/public-key\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-05T00:40:40.304Z\", \"description\": null, \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 11, \"path\": \"/api/v1/security/public-key\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:07:23.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-05T00:40:40.304Z\", \"description\": null, \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-05 00:40:40'),
(8, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 18, \"path\": \"/test\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:45:21.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-04T23:45:21.000Z\", \"description\": \"Test\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": false}', '{\"id\": 18, \"path\": \"/test/success\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"createdAt\": \"2025-05-04T23:45:21.000Z\", \"deletedAt\": null, \"methodInt\": 2, \"updatedAt\": \"2025-05-05T00:41:55.054Z\", \"description\": \"Test\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": false}', '2025-05-05 00:41:55'),
(9, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 18, \"path\": \"/test/success\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"methodInt\": 2, \"description\": \"Test\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": false}', '{\"id\": 18, \"path\": \"/test\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"methodInt\": 2, \"updatedAt\": \"2025-05-05T00:43:44.026Z\", \"description\": \"Test\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', '2025-05-05 00:43:44'),
(10, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/health\", \"method\": {\"original\": \"get\", \"translated\": \"enums.method.get\"}, \"methodInt\": 2, \"description\": null, \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"updatedAt\": \"2025-05-30T00:33:40.299Z\", \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:33:40'),
(11, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:35:12'),
(12, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:35:37'),
(13, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:35:41'),
(14, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:36:32'),
(15, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:37:07'),
(16, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:37:44'),
(17, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:38:06'),
(18, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:39:11'),
(19, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:39:36'),
(20, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:40:02'),
(21, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:47:15'),
(22, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:49:01'),
(23, '{\"id\": 1, \"rol\": {\"id\": 1, \"name\": \"administration\"}, \"safeMode\": false, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"contactData\": [{\"type\": \"email\", \"emails\": [\"santiago.c.a_10@hotmail.es\"]}, {\"type\": \"phone\", \"phones\": []}], \"completeName\": \"Santiago Correa\", \"firstLastName\": \"Correa\", \"secondLastName\": null}', 'config_endpoints', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '{\"id\": 1, \"path\": \"/api/v1/endpoint\", \"method\": {\"original\": \"post\", \"translated\": \"enums.method.post\"}, \"methodInt\": 1, \"description\": \"ventosus mollitia bos\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": true}', '2025-05-30 00:55:42'),
(24, '{\"id\": 1, \"rol\": {\"id\": 10, \"name\": \"Regular Client\"}, \"email\": \"santiagocorreaaguirre14@gmail.com\", \"safeMode\": true, \"firstName\": \"Santiago\", \"idAccount\": 1, \"secondName\": null, \"completeName\": \"Santiago Correa\", \"mobileNumber\": null, \"firstLastName\": \"Correa\", \"recoveryEmail\": null, \"secondLastName\": null, \"emailConfirmedAt\": \"2025-06-20T20:43:51.000Z\", \"mobileNumberConfirmedAt\": null, \"recoveryEmailConfirmedAt\": null}', 'config_endpoints', '{\"id\": 3, \"path\": \"/resend-confirmation-email\", \"method\": {\"original\": \"post\", \"translated\": \"POST\"}, \"version\": \"v1\", \"platform\": \"web\", \"methodInt\": 1, \"description\": null, \"endpointPath\": \"/web/v1/auth/resend-confirmation-email\", \"endpointGroup\": \"auth\", \"requiresAuthorization\": true, \"hasSensitiveInformation\": false}', '{\"id\": 3, \"path\": \"/resend-confirmation-email\", \"method\": {\"original\": \"post\", \"translated\": \"POST\"}, \"version\": \"v1\", \"platform\": \"web\", \"methodInt\": 1, \"updatedAt\": \"2025-06-24T23:09:08.930Z\", \"description\": null, \"endpointPath\": \"/web/v1/auth/resend-confirmation-email\", \"endpointGroup\": \"auth\", \"requiresAuthorization\": false, \"hasSensitiveInformation\": false}', '2025-06-24 23:09:08');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `payment_gateways`
--

CREATE TABLE `payment_gateways` (
  `id` int NOT NULL COMMENT 'Unique identifier of each payment gateway',
  `slug` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Payment method name slug',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Commercial name of the payment gateway provider.',
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Brief description of the payment gateway features.',
  `supports_refunds` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates if the gateway supports refunds.',
  `supports_partial_refunds` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates if the gateway supports partial refunds.',
  `supports_subscriptions` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates if the gateway supports recurring payments/subscriptions.',
  `supports_webhooks` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates if the gateway supports webhook notifications.',
  `min_amount` decimal(10,2) DEFAULT NULL COMMENT 'Minimum transaction amount supported by the gateway.',
  `max_amount` decimal(15,2) DEFAULT NULL COMMENT 'Maximum transaction amount supported by the gateway.',
  `processing_time` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Typical processing time (e.g., "instant", "1-3 business days").',
  `settlement_time` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Time to receive funds (e.g., "T+1", "T+2").',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Soft delete timestamp.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Master table for payment gateway providers.';

--
-- Volcado de datos para la tabla `payment_gateways`
--

INSERT INTO `payment_gateways` (`id`, `slug`, `name`, `description`, `supports_refunds`, `supports_partial_refunds`, `supports_subscriptions`, `supports_webhooks`, `min_amount`, `max_amount`, `processing_time`, `settlement_time`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 'bancolombia', 'Bancolombia', 'Bank transfer payments for Colombian customers via Bancolombia.', 1, 1, 0, 1, 1.00, 10000.00, 'Instant to 24 hours', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(2, 'nequi', 'Nequi', 'Digital wallet payments in Colombia powered by Bancolombia.', 1, 1, 0, 1, 0.10, 2000.00, 'Instant', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(3, 'pse', 'PSE', 'Colombian online banking payments through PSE (Pagos Seguros en Línea).', 1, 1, 0, 1, 0.50, 8000.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(4, 'mercado-pago', 'Mercado Pago', 'Leading payment gateway in Latin America, supporting cards, cash payments, and bank transfers.', 1, 1, 1, 1, 0.10, 20000.00, 'Instant', 'T+1 to T+3', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(5, 'stripe', 'Stripe', 'Global payments platform supporting cards, wallets, and local payment methods.', 1, 1, 1, 1, 0.50, 999999.99, 'Instant', 'T+2', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(6, 'paypal', 'PayPal', 'International digital payments system with broad currency support.', 1, 1, 1, 1, 1.00, 100000.00, 'Instant', 'T+0 to T+2', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(7, 'adyen', 'Adyen', 'Enterprise payment platform for omnichannel transactions worldwide.', 1, 1, 1, 1, 1.00, NULL, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(8, 'alipay', 'Alipay', 'Dominant Chinese digital wallet integrated with local banking systems.', 1, 1, 0, 1, 0.10, 50000.00, 'Instant', 'T+3', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(9, 'wechatpay', 'WeChat Pay', 'Payment solution within WeChat ecosystem for Chinese consumers.', 1, 1, 0, 1, 0.10, 50000.00, 'Instant', 'T+3', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(10, 'kakaopay', 'KakaoPay', 'South Korean mobile payment service via Kakao ecosystem.', 1, 1, 1, 1, 100.00, 1000000.00, 'Instant', 'T+2', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(11, 'poli', 'POLi', 'Bank transfer payments for Australia and New Zealand.', 1, 1, 0, 1, 1.00, 20000.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(12, 'mpesa', 'M-Pesa', 'Mobile money transfer service widely used across Africa.', 1, 1, 1, 1, 0.01, 10000.00, 'Instant', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(13, 'sofort', 'Sofort', 'Real-time bank transfers for Germany, Austria and neighboring countries.', 1, 1, 0, 1, 0.50, 35000.00, 'Instant', 'T+2', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(14, 'paypay', 'PayPay', 'Leading Japanese QR code payment wallet and online solution.', 1, 1, 0, 1, 1.00, 100000.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(15, 'sepa', 'SEPA Direct Debit', 'Eurozone direct debit system for recurring EU payments.', 1, 1, 1, 1, NULL, 100000.00, '1-3 business days', 'T+3', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(16, 'flutterwave', 'Flutterwave', 'Pan-African payment gateway supporting local methods.', 1, 1, 1, 1, 0.50, 250000.00, 'Instant', 'T+2', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(17, 'spei', 'SPEI', 'Mexican interbank electronic payment system.', 0, 0, 0, 1, 1.00, 15000.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(18, 'webpay', 'Webpay', 'Chilean payment gateway supporting cards/bank transfers.', 1, 1, 1, 1, 0.50, 10000.00, 'Instant', 'T+2', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(19, 'todopago', 'TodoPago', 'Argentinian payment solution for bank transfers/cash.', 1, 1, 0, 1, 0.50, 5000.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(20, 'pix', 'PIX', 'Brazilian instant bank transfer system.', 1, 1, 0, 1, 0.01, 10000.00, 'Instant', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(21, 'mbway', 'MB WAY', 'Portuguese mobile payment solution.', 1, 1, 0, 1, 0.50, 500.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(22, 'bizum', 'Bizum', 'Spanish instant mobile payment system.', 1, 1, 0, 1, 0.50, 1000.00, 'Instant', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(23, 'paylib', 'Paylib', 'French mobile payment solution.', 1, 1, 1, 1, 1.00, 3000.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(24, 'satispay', 'Satispay', 'Italian mobile payment network.', 1, 1, 1, 1, 0.50, 1500.00, 'Instant', 'T+1', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(25, 'paytabs', 'PayTabs', 'Middle Eastern gateway supporting cards/local methods.', 1, 1, 1, 1, 1.00, 50000.00, 'Instant', 'T+2', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(26, 'yoomoney', 'YooMoney', 'Russian digital wallet and bank transfer solution.', 1, 1, 1, 1, 0.50, 10000.00, 'Instant', 'T+1 to T+3', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(27, 'coinbase', 'Coinbase Wallet', 'Self-custody crypto wallet by Coinbase supporting multiple blockchains.', 1, 1, 0, 1, 1.00, 100000.00, 'Instant to 30 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(28, 'trustwallet', 'Trust Wallet', 'Binance-owned multi-coin wallet with DeFi integration.', 1, 1, 0, 1, 0.50, 50000.00, '1-15 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(29, 'metamask', 'MetaMask', 'Leading Ethereum wallet with Web3 browser integration.', 1, 1, 0, 1, 0.10, 50000.00, '1-10 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(30, 'bitpay', 'BitPay', 'Enterprise crypto payment processor supporting multiple coins.', 1, 1, 1, 1, 5.00, 100000.00, 'Instant to 15 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(31, 'binancepay', 'Binance Pay', 'Crypto payment solution within Binance ecosystem.', 1, 1, 1, 1, 1.00, 1000000.00, 'Instant', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(32, 'cryptocom', 'Crypto.com Pay', 'Payment solution with crypto rewards and Visa integration.', 1, 1, 1, 1, 1.00, 500000.00, 'Instant to 5 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(33, 'exodus', 'Exodus Wallet', 'Multi-asset wallet with built-in exchange features.', 1, 1, 0, 1, 1.00, 20000.00, '1-30 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(34, 'phantom', 'Phantom', 'Solana ecosystem wallet with NFT and DeFi support.', 1, 1, 0, 1, 0.10, 10000.00, 'Instant to 2 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(35, 'coinspot', 'CoinSpot', 'Australian-based multi-cryptocurrency wallet.', 1, 1, 0, 1, 10.00, 50000.00, 'Instant to 10 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL),
(36, 'blockchain', 'Blockchain.com', 'Long-standing crypto wallet supporting Bitcoin and other cryptocurrencies.', 1, 1, 0, 1, 0.50, 100000.00, '5-30 minutes', 'T+0', '2025-08-16 22:08:09', '2025-08-16 22:08:09', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `payment_gateways_has_countries_currencies`
--

CREATE TABLE `payment_gateways_has_countries_currencies` (
  `id` int NOT NULL COMMENT 'Unique identifier for each relationship between payment gateway, country, and currency.',
  `payment_gateway_id` int NOT NULL COMMENT 'Payment gateway ID.',
  `country_currency_id` int NOT NULL COMMENT 'Currency-country relationship ID. This makes it easier to find the countries in which the payment gateway can operate and which currencies.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship between payment gateway, country and currency.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `payment_gateways_links`
--

CREATE TABLE `payment_gateways_links` (
  `id` int NOT NULL COMMENT 'Unique identifier of each link belonging to a payment gateway.',
  `payment_gateway_id` int NOT NULL COMMENT 'Payment gateway ID.',
  `link_type` enum('documentation','api_reference','webhook_config','credentials','sandbox','production','dashboard','support','pricing','status_page','changelog','sdk','postman_collection','other') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Type of link for categorization.',
  `title` varchar(255) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Descriptive title of the link.',
  `url` text COLLATE utf8mb4_general_ci NOT NULL COMMENT 'The actual URL/link.',
  `description` text COLLATE utf8mb4_general_ci COMMENT 'Optional detailed description of what this link contains.',
  `environment` enum('sandbox','production','both','general') COLLATE utf8mb4_general_ci DEFAULT 'general' COMMENT 'Environment this link applies to.',
  `is_active` tinyint(1) DEFAULT '1' COMMENT 'Whether the link is still valid/active.',
  `requires_auth` tinyint(1) DEFAULT '0' COMMENT 'Whether accessing this link requires authentication.',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When the link was added.',
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'When the link was last updated.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Important links to docs and config of payment gateways.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `payment_gateway_has_clients_credentials`
--

CREATE TABLE `payment_gateway_has_clients_credentials` (
  `id` int NOT NULL COMMENT 'Unique identifier for each credential.',
  `payment_gateway_id` int NOT NULL COMMENT 'ID of the payment gateway.',
  `client_id` int NOT NULL COMMENT 'ID of the company that owns these credentials.',
  `environment` enum('sandbox','production') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'sandbox' COMMENT 'Environment type for these credentials.',
  `credential_data` json NOT NULL COMMENT 'Encrypted JSON object containing all necessary credentials (API keys, secrets, etc.).',
  `is_primary` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates if this is the primary credential set for this gateway/company.',
  `expires_at` timestamp NULL DEFAULT NULL COMMENT 'Expiration date for the credentials (if applicable).',
  `validation_status` enum('pending','valid','invalid','expired') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT 'pending' COMMENT 'Current validation status.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Soft delete timestamp.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Stores encrypted credentials for each company and payment gateway combination.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `payment_gateway_webhooks`
--

CREATE TABLE `payment_gateway_webhooks` (
  `id` int NOT NULL COMMENT 'Unique identifier for each webhook.',
  `payment_gateway_id` int NOT NULL COMMENT 'ID of the company that owns this webhook.',
  `client_id` int NOT NULL COMMENT 'ID of the payment gateway.',
  `id_webhook` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'External webhook ID from the payment gateway (if applicable).',
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Descriptive name for this webhook.',
  `endpoint_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'URL endpoint that will receive the webhook.',
  `secret_key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Secret key for webhook signature verification.',
  `events` json NOT NULL COMMENT 'Array of events this webhook should listen to.',
  `environment` enum('sandbox','production') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'sandbox' COMMENT 'Environment for this webhook.',
  `delivery_success_count` int NOT NULL DEFAULT '0' COMMENT 'Number of successful deliveries.',
  `delivery_failure_count` int NOT NULL DEFAULT '0' COMMENT 'Number of failed deliveries.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Soft delete timestamp.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Webhook configurations for payment gateways.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_actions`
--

CREATE TABLE `prj_actions` (
  `id` int NOT NULL COMMENT 'Unique identifier for each action.',
  `id_goal` int NOT NULL COMMENT 'ID of the goal to be met with the actions.',
  `id_parent` int DEFAULT NULL COMMENT 'ID of the action to which this belongs.',
  `name` varchar(250) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name or title of the action.',
  `description` longtext COLLATE utf8mb4_general_ci COMMENT 'Description details of the action.',
  `start_datetime` timestamp NOT NULL COMMENT 'Date and time of commencement of the action.',
  `due_datetime` timestamp NULL DEFAULT NULL COMMENT 'Date and time the action is expected to complete. If null, it indicates that this is not an expiring action.',
  `finish_datetime` timestamp NULL DEFAULT NULL COMMENT 'Date and time the action is expected to be completed.',
  `status` enum('pending','in_progress','under_review','completed') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Status of the action.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Activities, events or tasks to achieve the goal.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_goals`
--

CREATE TABLE `prj_goals` (
  `id` int NOT NULL COMMENT 'Unique identifier for each goal.',
  `id_project` int NOT NULL COMMENT 'ID of the project to which the goal belongs.',
  `objective` varchar(200) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Objective of the goal to be achieved.',
  `description` longtext COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Goal details.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Project goals.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_projects`
--

CREATE TABLE `prj_projects` (
  `id` int NOT NULL COMMENT 'Unique identifier for each project.',
  `id_company` int NOT NULL COMMENT 'ID of the company to which the project is associated.',
  `id_type` int NOT NULL COMMENT 'Project type ID.',
  `id_subtype` int DEFAULT NULL COMMENT 'Project subtype ID (if applicable).',
  `code` varchar(100) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique code for each project.',
  `name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Project name.',
  `description` text COLLATE utf8mb4_general_ci COMMENT 'Project description.',
  `status` enum('pending','in_progress','completed') COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending' COMMENT 'Project status.',
  `priority` enum('low','medium','high') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Priority level at which the project should be executed.',
  `start_date` date NOT NULL COMMENT 'Project start date.',
  `finish_date` date NOT NULL COMMENT 'Project completion date.',
  `total_budget` decimal(18,2) NOT NULL COMMENT 'Total budget for the execution of the project.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Basic project information.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_projects_has_accounts`
--

CREATE TABLE `prj_projects_has_accounts` (
  `id` int NOT NULL COMMENT 'Unique identifier for each relationship between projects and actors.',
  `id_project` int NOT NULL COMMENT 'ID of the project to which the account is associated.',
  `id_account` int NOT NULL COMMENT 'ID of the account to which the project is associated.',
  `id_role` int NOT NULL COMMENT 'ID of the role that the account holds for the project.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relationship of accounts with projects.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_project_sub_types`
--

CREATE TABLE `prj_project_sub_types` (
  `id` int NOT NULL COMMENT 'Unique identifier for each project subtype.',
  `id_type` int NOT NULL COMMENT 'ID of the type to which the subtype is associated.',
  `name` json NOT NULL COMMENT 'Subtype name.',
  `description` json NOT NULL COMMENT 'Subtype description.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Project subtypes.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_project_types`
--

CREATE TABLE `prj_project_types` (
  `id` int NOT NULL COMMENT 'Unique identifier for each project type.',
  `name` json NOT NULL COMMENT 'Name of the project type.',
  `description` json DEFAULT NULL COMMENT 'Description of the type of project.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='General types of projects.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_socializations`
--

CREATE TABLE `prj_socializations` (
  `id` int NOT NULL COMMENT 'Unique identifier for each socialization.',
  `id_project_account` int NOT NULL COMMENT 'ID of the relationship between project and account.',
  `id_project` int NOT NULL COMMENT 'ID of the project being socialized.',
  `id_goal` int DEFAULT NULL COMMENT 'ID of the goal that is being socialized.',
  `id_action` int DEFAULT NULL COMMENT 'ID of the action being socialized.',
  `id_parent` int DEFAULT NULL COMMENT 'ID of the message or socialization being responded to.',
  `text` longtext COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Socialization text or message.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Socialization about the project, goal or action.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prj_supports`
--

CREATE TABLE `prj_supports` (
  `id` int NOT NULL COMMENT 'Unique identifier for each project support.',
  `id_project` int NOT NULL COMMENT 'ID of the project to which the support belongs.',
  `id_goal` int DEFAULT NULL COMMENT 'ID of the project meta to which the support belongs.',
  `id_action` int DEFAULT NULL COMMENT 'ID of the action to which the support belongs.',
  `path` varchar(100) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Support file path.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Project, goal or action supports.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_accounts_has_employee`
--

CREATE TABLE `sup_accounts_has_employee` (
  `id` int NOT NULL COMMENT 'Unique identifier for each account-support employee relationship.',
  `id_account` int NOT NULL COMMENT 'ID of the account that will be accessed as support.',
  `id_employee` int NOT NULL COMMENT 'ID of the support employee who will access the user''s account.',
  `state` enum('requested','pending','approved','rejected','finished') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'requested' COMMENT 'Indicates the status of the user''s support. It starts out as ''requested'', which indicates that an email has been sent by the support staff to the user for approval; ''pending'' for when the user accesses the permissions view; ''approved'' for when the user accepts access to their account, with the chosen permissions; ''rejected'' for when the user indicates that they do not accept access to their account; ''finished'' for when the time has run out or the support staff has logged out.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Support access to other accounts.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_externals`
--

CREATE TABLE `sup_externals` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each user who creates a ticket but does not have an account on the platform.',
  `name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Name of the user who is not registered on the platform but created a ticket.',
  `lastname` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Last name of the user who is not registered on the platform but created a ticket.',
  `email` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Email address (for support and validation of an existing account on the platform) of the user who opened a ticket but is presumed not to be registered on the platform.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Information about unregistered users who created a ticket.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_faq`
--

CREATE TABLE `sup_faq` (
  `id` int NOT NULL COMMENT 'Unique identifier for each FAQ.',
  `id_page` int DEFAULT NULL COMMENT 'ID of the page associated with the FAQ.',
  `id_item` int DEFAULT NULL COMMENT 'ID of the service or product offered to the public.',
  `question` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Frequently Asked Question.',
  `answer` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'FAQ Answer. It can be stored as HTML, or as MarkDown.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Frequently asked questions for each page.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_pqrs`
--

CREATE TABLE `sup_pqrs` (
  `id` int NOT NULL COMMENT 'Unique identifier for each PQRS request.',
  `id_ticket` int DEFAULT NULL COMMENT 'Associated ticket ID, if any.',
  `type` enum('petition','complaint','claim','suggestion') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Type of PQRS request.',
  `description` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Detailed description of the PQRS request.',
  `status` enum('created','in_process','resolved','closed') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'created' COMMENT 'Current status of the PQRS request.',
  `response` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Response or resolution to the PQRS request.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the PQRS request was created.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the PQRS request was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table to store PQRS requests.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_responses`
--

CREATE TABLE `sup_responses` (
  `id` int NOT NULL COMMENT 'Unique identifier for each response.',
  `id_ticket` int NOT NULL COMMENT 'Associated ticket ID.',
  `response_type` enum('internal','external') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Type of response: internal (for staff) or external (for end-user).',
  `content` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Response content, including notes or public responses.',
  `created_by` int NOT NULL COMMENT 'User ID of the person who created the response.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the response was created.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table to manage responses associated with tickets.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_tickets`
--

CREATE TABLE `sup_tickets` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each ticket.',
  `id_account` int DEFAULT NULL COMMENT 'User account ID of the person who created the ticket. It is null if it was created by an unregistered person.',
  `id_external` int DEFAULT NULL COMMENT 'ID of the user who created the ticket but is not registered on the platform.',
  `id_asignee` int DEFAULT NULL COMMENT 'User ID of the person (account) assigned to resolve the ticket.',
  `id_type` int NOT NULL COMMENT 'ID of the ticket type with which the ticket was created.',
  `subject` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Subject or title of the ticket. A very brief summary of what is happening.',
  `details` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Details of the issue the end user is experiencing, if they wish to go into more depth on the topic.',
  `status` enum('created','under_review','answered','reopened','resolved','closed') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'created' COMMENT 'Ticket status. `created` for newly created tickets, `under_review` when the ticket is being reviewed by the support team, `answered` when the ticket has received an initial response from the support team, `reopened` when it was reported that the ticket has not been resolved and requires further analysis, `resolved` when the ticket has been resolved and the person who created it has been notified, and `closed` when one week has passed since the ticket was resolved or no response has been received from the person who created the ticket.',
  `priority` enum('task','low','medium','high','critic') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'task' COMMENT 'Ticket priority. `task` for tickets that refer more to a suggestion and can be included in the development flow, `low` for tickets that correspond to a correction that can wait a longer period, `medium` for tickets that need to be resolved within the next few days, `high` for tickets that must be resolved within the next 1-2 days, and `critical` for tickets that need to be resolved within a few hours.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.',
  `id_pqrs` int DEFAULT NULL COMMENT 'Associated PQRS ID, if any.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores tickets.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_tickets_assets`
--

CREATE TABLE `sup_tickets_assets` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each asset.',
  `id_ticket` int NOT NULL COMMENT 'ID of the ticket to which this resource belongs.',
  `path` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'URL (complete or partial) to the resource uploaded by the end user for the ticket they created.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table containing ticket support resources.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sup_tickets_types`
--

CREATE TABLE `sup_tickets_types` (
  `id` int NOT NULL COMMENT 'Unique primary key to identify each available ticket type.',
  `name` json NOT NULL COMMENT 'Name of the ticket type. Written in various languages, as it is planned to be displayed to the end user.',
  `description` json NOT NULL COMMENT 'Description of the ticket, written in various languages so that the end user, regardless of their language, understands what type of ticket they are creating.',
  `sampling_order` tinyint NOT NULL DEFAULT '1' COMMENT 'Order in which the ticket types will be displayed to the user, also used for filtering them.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.',
  `is_pqrs` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates if the ticket type is related to PQRS.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the different types of tickets available.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_accesses`
--

CREATE TABLE `usr_accesses` (
  `id` int NOT NULL COMMENT 'Unique identifier for each access.',
  `account_id` int NOT NULL COMMENT 'Account ID.',
  `id_token` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Unique ID of the encrypted JWT token (not the primary key because it is recommended to encrypt it).',
  `payload` json NOT NULL COMMENT 'Payload stored for future sessions to compare.',
  `reliable` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether the device is trusted or not.',
  `safe_mode` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether access was performed in safe mode.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Log of account access and devices.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_accounts`
--

CREATE TABLE `usr_accounts` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each account belonging to a user.',
  `rol_id` int NOT NULL COMMENT 'ID of the role that holds the account.',
  `user_id` int DEFAULT NULL COMMENT 'User/customer ID associated with the account.',
  `employee_id` int DEFAULT NULL COMMENT 'ID of the user to whom the account belongs.',
  `dial_code_id` int DEFAULT NULL COMMENT 'Mobile number code ID. Cannot be null if a cell phone number exists.',
  `internal_code` varchar(20) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Internal code assigned to each account.',
  `email` varchar(150) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Primary email address for the account to access the platform.',
  `email_confirmed_at` timestamp NULL DEFAULT NULL COMMENT 'Indicates whether the email address has already been confirmed (other than null) or not (null).',
  `recovery_email` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Email account where recovery data will be sent, in case the primary account cannot be accessed.',
  `recovery_email_confirmed_at` timestamp NULL DEFAULT NULL COMMENT 'Indicates whether the recovery email has already been confirmed (other than null) or not (null).',
  `mobile_number` varchar(30) COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Mobile phone number of the account.',
  `mobile_number_confirmed_at` timestamp NULL DEFAULT NULL COMMENT 'Indicates whether the mobile number has already been confirmed (other than null) or not (null).',
  `password` blob NOT NULL COMMENT 'Hash of the user''s access password. It is encrypted for enhanced security of the user''s information.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Contains information about a user''s account.';

--
-- Volcado de datos para la tabla `usr_accounts`
--

INSERT INTO `usr_accounts` (`id`, `rol_id`, `user_id`, `employee_id`, `dial_code_id`, `internal_code`, `email`, `email_confirmed_at`, `recovery_email`, `recovery_email_confirmed_at`, `mobile_number`, `mobile_number_confirmed_at`, `password`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 10, 1, NULL, NULL, 'MDAOX7C6HVMUR516', 'santiago.c.a_10@hotmail.es', '2025-07-19 15:18:58', NULL, NULL, NULL, NULL, 0x553246736447566b5831384f57794959433067374744344b2f3655705133634f567a38696b635731306f356d755a744646454377417166624e592f537947756f776b3852724d6b434c6d6e344f754d7a42463957654a67314c59544941715238314359683433505a4162513d, '2025-07-19 20:18:22', '2025-07-19 20:19:01', NULL);

--
-- Disparadores `usr_accounts`
--
DELIMITER $$
CREATE TRIGGER `usr_accounts_reset_confirmations_before_update` BEFORE UPDATE ON `usr_accounts` FOR EACH ROW BEGIN

    IF OLD.email != NEW.email THEN
        SET NEW.email_confirmed_at = NULL;
    END IF;

    IF (OLD.recovery_email IS NULL AND NEW.recovery_email IS NOT NULL) OR 
       (OLD.recovery_email IS NOT NULL AND NEW.recovery_email IS NULL) OR
       (OLD.recovery_email != NEW.recovery_email) THEN
        SET NEW.recovery_email_confirmed_at = NULL;
    END IF;

    IF (OLD.mobile_number IS NULL AND NEW.mobile_number IS NOT NULL) OR 
       (OLD.mobile_number IS NOT NULL AND NEW.mobile_number IS NULL) OR
       (OLD.mobile_number != NEW.mobile_number) THEN
        SET NEW.mobile_number_confirmed_at = NULL;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_accounts_has_scopes`
--

CREATE TABLE `usr_accounts_has_scopes` (
  `id` int NOT NULL COMMENT 'Unique identifier for each relationship between an account and a scope.',
  `account_id` int NOT NULL COMMENT 'Account ID.',
  `scope_id` int NOT NULL COMMENT 'Scope ID.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Temporary scopes that a specific account can have.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_employees`
--

CREATE TABLE `usr_employees` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each user.',
  `id_country` int DEFAULT NULL COMMENT 'ID of the country where the user was born (their country of birth).',
  `id_city` int DEFAULT NULL COMMENT 'ID of the city where the user currently resides.',
  `id_identification_type` int DEFAULT NULL COMMENT 'ID of the user''s identification type.',
  `document` bigint DEFAULT NULL COMMENT 'Identification document number of the user, without special characters, punctuation, or letters.',
  `first_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'First name of the user.',
  `second_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Middle name(s) of the user.',
  `first_lastname` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'First surname of the user (usually the paternal surname).',
  `second_lastname` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Second surname(s) of the user.',
  `birthday` date DEFAULT NULL COMMENT 'Date of birth of the user. Typically used for birthday greetings and/or age validation.',
  `address` tinytext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci COMMENT 'Physical address of the user''s residence.',
  `gender` enum('male','female','other','undefined') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'undefined' COMMENT 'Biological sex assigned at birth or gender identity, if applicable.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores personal information of each user.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_images`
--

CREATE TABLE `usr_images` (
  `id` int NOT NULL COMMENT 'Unique identifier for each image.',
  `id_account` int NOT NULL COMMENT 'ID of the account to which the image belongs.',
  `type` enum('profile','front_page') COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Indicates the type of account image.',
  `path` varchar(150) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Image path.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Profile and/or cover images for each account.';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_preferences`
--

CREATE TABLE `usr_preferences` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each created preference.',
  `id_account` int NOT NULL COMMENT 'ID of the account to which the preferences belong.',
  `id_language` int NOT NULL COMMENT 'ID of the language selected by the user as their preference.',
  `id_timezone` int NOT NULL COMMENT 'ID of the time zone that the user selects as their preference for the platform.',
  `theme` enum('ligth','dark') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'ligth' COMMENT 'Preferred theme type (color scheme) of the platform for the user.',
  `whatsapp` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates whether you allow receiving notifications via WhatsApp.',
  `sms` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether you allow receiving SMS notifications.',
  `email` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether you allow receiving notifications and/or advertising by email.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores user preferences (settings).';

--
-- Volcado de datos para la tabla `usr_preferences`
--

INSERT INTO `usr_preferences` (`id`, `id_account`, `id_language`, `id_timezone`, `theme`, `whatsapp`, `sms`, `email`) VALUES
(1, 1, 154, 80, 'dark', 0, 1, 1);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_tokens`
--

CREATE TABLE `usr_tokens` (
  `id` int NOT NULL COMMENT 'Unique primary key for identifying each created token.',
  `account_id` int NOT NULL COMMENT 'ID of the user''s account for which the token was created.',
  `id_token` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'JTI of the JWT token.',
  `purpose` enum('confirm_email','confirm_recovery_email','confirm_phone','recover_password') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'Purpose of the token.',
  `payload` json DEFAULT NULL COMMENT 'Token payload in case you want to send it again.',
  `expires_in` timestamp NOT NULL COMMENT 'Indicates the date and time limit for the use of the token.',
  `used_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time the token was used.',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table that stores the purpose and information of tokens.';

--
-- Volcado de datos para la tabla `usr_tokens`
--

INSERT INTO `usr_tokens` (`id`, `account_id`, `id_token`, `purpose`, `payload`, `expires_in`, `used_at`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, '8ed2809a-b6cb-4ba4-9bf1-143a4c27c51b', 'confirm_email', NULL, '2025-07-20 20:18:22', '2025-07-19 15:18:47', '2025-07-19 20:18:22', '2025-07-19 20:18:50', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usr_users`
--

CREATE TABLE `usr_users` (
  `id` int NOT NULL COMMENT 'Unique identifier of each client.',
  `first_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'First name of the user/customer.',
  `second_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Second name of the user/client (if applicable).',
  `first_last_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'First surname of the user/customer.',
  `second_last_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Second surname of the user/client (if applicable).',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date and time when the record was created in the table.	',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Date and time when the record was last modified.',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Date and time when the record was deactivated. If the value is null, it means the record is still active; otherwise, it indicates that the record has been deactivated (known as soft deletion), without removing the information from the table.'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Basic information about users/employees.';

--
-- Volcado de datos para la tabla `usr_users`
--

INSERT INTO `usr_users` (`id`, `first_name`, `second_name`, `first_last_name`, `second_last_name`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 'Santiago', NULL, 'Correa', NULL, '2025-07-19 20:18:22', '2025-07-19 20:18:22', NULL);

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `ai_assistants`
--
ALTER TABLE `ai_assistants`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `cli_branches`
--
ALTER TABLE `cli_branches`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `internal_code_UN` (`internal_code`),
  ADD UNIQUE KEY `branch_code_UN` (`branch_code`),
  ADD KEY `company` (`company_id`),
  ADD KEY `country` (`country_id`),
  ADD KEY `city` (`city_id`);

--
-- Indices de la tabla `cli_companies`
--
ALTER TABLE `cli_companies`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `document_UN` (`legal_document`,`id_tax`),
  ADD KEY `country` (`country_id`),
  ADD KEY `city` (`city_id`);

--
-- Indices de la tabla `cli_contacts`
--
ALTER TABLE `cli_contacts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `branch` (`branch_id`),
  ADD KEY `department` (`department_id`);

--
-- Indices de la tabla `cli_departments`
--
ALTER TABLE `cli_departments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code_UN` (`internal_code`),
  ADD KEY `company` (`company_id`),
  ADD KEY `branch` (`branch_id`),
  ADD KEY `parent_department` (`parent_department_id`);

--
-- Indices de la tabla `cli_social_networks`
--
ALTER TABLE `cli_social_networks`
  ADD PRIMARY KEY (`id`),
  ADD KEY `company` (`company_id`);

--
-- Indices de la tabla `config_endpoints`
--
ALTER TABLE `config_endpoints`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `endpoint_UN` (`method`,`platform`,`version`,`endpoint_group`,`path`);

--
-- Indices de la tabla `config_endpoints_has_required_scopes`
--
ALTER TABLE `config_endpoints_has_required_scopes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `endpoint` (`endpoint_id`),
  ADD KEY `scope` (`scope_id`);

--
-- Indices de la tabla `config_endpoints_request_schema`
--
ALTER TABLE `config_endpoints_request_schema`
  ADD PRIMARY KEY (`id`),
  ADD KEY `endpoint` (`endpoint_id`),
  ADD KEY `field` (`field_id`);

--
-- Indices de la tabla `config_hosts`
--
ALTER TABLE `config_hosts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `url_UN` (`url`),
  ADD KEY `company` (`company_id`);

--
-- Indices de la tabla `config_pages`
--
ALTER TABLE `config_pages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `parent` (`page_id`),
  ADD KEY `host` (`host_id`),
  ADD KEY `parent_page` (`page_id`);

--
-- Indices de la tabla `config_pages_endpoints_has_schemas`
--
ALTER TABLE `config_pages_endpoints_has_schemas`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `page_endpoint_schema_UN` (`id_page_endpoint`,`id_endpoint_field`),
  ADD KEY `page_endpoint` (`id_page_endpoint`),
  ADD KEY `endpoint_field` (`id_endpoint_field`);

--
-- Indices de la tabla `config_pages_has_endpoints`
--
ALTER TABLE `config_pages_has_endpoints`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `page_endpoint` (`id_page`,`id_endpoint`),
  ADD KEY `page` (`id_page`),
  ADD KEY `endpoint` (`id_endpoint`);

--
-- Indices de la tabla `config_pages_has_required_scopes`
--
ALTER TABLE `config_pages_has_required_scopes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `page` (`page_id`),
  ADD KEY `scope` (`scope_id`);

--
-- Indices de la tabla `config_roles`
--
ALTER TABLE `config_roles`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `config_roles_has_scopes`
--
ALTER TABLE `config_roles_has_scopes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `role` (`role_id`);

--
-- Indices de la tabla `config_scopes`
--
ALTER TABLE `config_scopes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `scope_name_UN` (`name`);

--
-- Indices de la tabla `config_shorteners`
--
ALTER TABLE `config_shorteners`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `url_code_shortener_UN` (`url`,`code_shortener`);

--
-- Indices de la tabla `config_taxes`
--
ALTER TABLE `config_taxes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `country_fk` (`id_country`),
  ADD KEY `sub_division_fk` (`id_sub_division`),
  ADD KEY `city_fk` (`id_city`);

--
-- Indices de la tabla `data_currencies`
--
ALTER TABLE `data_currencies`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_abbreviation` (`abbreviation`);

--
-- Indices de la tabla `data_flags`
--
ALTER TABLE `data_flags`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `flag_name` (`name`),
  ADD UNIQUE KEY `location` (`location`),
  ADD UNIQUE KEY `flat_2d` (`flat_2d`),
  ADD UNIQUE KEY `rounded_2d` (`rounded_2d`),
  ADD UNIQUE KEY `wave_2d` (`wave_2d`),
  ADD UNIQUE KEY `flat_3d` (`flat_3d`),
  ADD UNIQUE KEY `wave_3d` (`wave_3d`),
  ADD KEY `rounded_3d` (`rounded_3d`);

--
-- Indices de la tabla `data_languages`
--
ALTER TABLE `data_languages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `flag` (`id_flag`);

--
-- Indices de la tabla `data_timezones`
--
ALTER TABLE `data_timezones`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name_timezone` (`name`) COMMENT 'Name of the time zone.',
  ADD KEY `continent` (`id_continent`) COMMENT 'Continent to which the time zone belongs.';

--
-- Indices de la tabla `data_types_identification`
--
ALTER TABLE `data_types_identification`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `country_document` (`id_country`,`abbreviation`),
  ADD KEY `country` (`id_country`);

--
-- Indices de la tabla `doc_categories`
--
ALTER TABLE `doc_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `doc_documents`
--
ALTER TABLE `doc_documents`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `document_UN` (`name`,`type`),
  ADD KEY `category` (`id_category`);

--
-- Indices de la tabla `doc_documents_access`
--
ALTER TABLE `doc_documents_access`
  ADD PRIMARY KEY (`id`),
  ADD KEY `document` (`id_document`),
  ADD KEY `account` (`id_account`);

--
-- Indices de la tabla `doc_metadata`
--
ALTER TABLE `doc_metadata`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `document_UN` (`id_document`),
  ADD KEY `document` (`id_document`);

--
-- Indices de la tabla `doc_permissions`
--
ALTER TABLE `doc_permissions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `account` (`id_account`),
  ADD KEY `role` (`id_role`),
  ADD KEY `document` (`id_document`),
  ADD KEY `supervisor` (`id_supervisor`);

--
-- Indices de la tabla `doc_supervisors`
--
ALTER TABLE `doc_supervisors`
  ADD PRIMARY KEY (`id`),
  ADD KEY `supervisor` (`id_employee`),
  ADD KEY `category` (`id_category`),
  ADD KEY `document` (`id_document`);

--
-- Indices de la tabla `doc_versions`
--
ALTER TABLE `doc_versions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `document` (`id_document`),
  ADD KEY `creator` (`id_creator`);

--
-- Indices de la tabla `doc_versions_socializations`
--
ALTER TABLE `doc_versions_socializations`
  ADD PRIMARY KEY (`id`),
  ADD KEY `version` (`id_version`),
  ADD KEY `account` (`id_account`),
  ADD KEY `supervisor` (`id_supervisor`),
  ADD KEY `socialization` (`id_socialization`);

--
-- Indices de la tabla `fin_budgets`
--
ALTER TABLE `fin_budgets`
  ADD PRIMARY KEY (`id`),
  ADD KEY `project` (`id_project`);

--
-- Indices de la tabla `fin_cashboxes`
--
ALTER TABLE `fin_cashboxes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `responsible` (`id_contract`),
  ADD KEY `project` (`id_project`);

--
-- Indices de la tabla `fin_invoices`
--
ALTER TABLE `fin_invoices`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `item` (`id_item`),
  ADD KEY `client` (`id_account`);

--
-- Indices de la tabla `fin_invoices_details`
--
ALTER TABLE `fin_invoices_details`
  ADD PRIMARY KEY (`id`),
  ADD KEY `invoice` (`id_invoice`),
  ADD KEY `item` (`id_item`);

--
-- Indices de la tabla `fin_ledger_accounts`
--
ALTER TABLE `fin_ledger_accounts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code_UN` (`code`),
  ADD KEY `company` (`id_company`),
  ADD KEY `ledger_account` (`id_parent`);

--
-- Indices de la tabla `fin_transactions`
--
ALTER TABLE `fin_transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `account` (`id_account`),
  ADD KEY `ledger_account` (`id_ledger_account`);

--
-- Indices de la tabla `geo_cities`
--
ALTER TABLE `geo_cities`
  ADD PRIMARY KEY (`id`),
  ADD KEY `sub_division` (`id_sub_division`),
  ADD KEY `timezone` (`id_timezone`);

--
-- Indices de la tabla `geo_continents`
--
ALTER TABLE `geo_continents`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `abbreviation` (`abbreviation`) COMMENT 'Unique abbreviation for each continent.';

--
-- Indices de la tabla `geo_countries`
--
ALTER TABLE `geo_countries`
  ADD PRIMARY KEY (`id`),
  ADD KEY `region` (`id_region`),
  ADD KEY `capital` (`id_capital`),
  ADD KEY `flag` (`id_flag`);

--
-- Indices de la tabla `geo_countries_has_currencies`
--
ALTER TABLE `geo_countries_has_currencies`
  ADD PRIMARY KEY (`id`),
  ADD KEY `country` (`country_id`),
  ADD KEY `currency` (`currency_id`) USING BTREE;

--
-- Indices de la tabla `geo_countries_has_languages`
--
ALTER TABLE `geo_countries_has_languages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `country` (`id_country`),
  ADD KEY `language` (`id_language`);

--
-- Indices de la tabla `geo_dial_codes`
--
ALTER TABLE `geo_dial_codes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`id_country`,`code`),
  ADD KEY `country` (`id_country`);

--
-- Indices de la tabla `geo_regions`
--
ALTER TABLE `geo_regions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `continent` (`id_continent`);

--
-- Indices de la tabla `geo_sub_divisions`
--
ALTER TABLE `geo_sub_divisions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `country` (`id_country`),
  ADD KEY `capital` (`id_capital`);

--
-- Indices de la tabla `hr_contracts`
--
ALTER TABLE `hr_contracts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `contract_number` (`contract_number`);

--
-- Indices de la tabla `inv_categories`
--
ALTER TABLE `inv_categories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `type` (`id_type`);

--
-- Indices de la tabla `inv_company_assets`
--
ALTER TABLE `inv_company_assets`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `contract` (`id_contract`);

--
-- Indices de la tabla `inv_contracts_has_assets`
--
ALTER TABLE `inv_contracts_has_assets`
  ADD PRIMARY KEY (`id`),
  ADD KEY `contract` (`id_contract`),
  ADD KEY `asset` (`id_asset`);

--
-- Indices de la tabla `inv_contracts_has_items`
--
ALTER TABLE `inv_contracts_has_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `contract` (`id_contract`),
  ADD KEY `item` (`id_item`);

--
-- Indices de la tabla `inv_details`
--
ALTER TABLE `inv_details`
  ADD PRIMARY KEY (`id`),
  ADD KEY `item` (`id_item`),
  ADD KEY `inv_details_ibfk_2` (`id_asset`);

--
-- Indices de la tabla `inv_inventories`
--
ALTER TABLE `inv_inventories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `branch` (`id_branch`),
  ADD KEY `warehouse` (`id_warehouse`),
  ADD KEY `contract` (`id_contract`);

--
-- Indices de la tabla `inv_inventories_details`
--
ALTER TABLE `inv_inventories_details`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `inventory_states` (`id_inventory`,`id_state`,`id_item`,`id_asset`),
  ADD KEY `item` (`id_item`),
  ADD KEY `asset` (`id_asset`),
  ADD KEY `inventory` (`id_inventory`),
  ADD KEY `state` (`id_state`);

--
-- Indices de la tabla `inv_inventories_states`
--
ALTER TABLE `inv_inventories_states`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `inv_items`
--
ALTER TABLE `inv_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `category` (`id_category`);

--
-- Indices de la tabla `inv_items_overrides`
--
ALTER TABLE `inv_items_overrides`
  ADD PRIMARY KEY (`id`),
  ADD KEY `item` (`id_item`);

--
-- Indices de la tabla `inv_movements`
--
ALTER TABLE `inv_movements`
  ADD PRIMARY KEY (`id`),
  ADD KEY `item` (`id_item`),
  ADD KEY `asset` (`id_asset`),
  ADD KEY `warehouse` (`id_warehouse`),
  ADD KEY `movement` (`id_movement`),
  ADD KEY `contract` (`id_contract`),
  ADD KEY `type` (`id_type`);

--
-- Indices de la tabla `inv_movements_types`
--
ALTER TABLE `inv_movements_types`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `inv_types_categories`
--
ALTER TABLE `inv_types_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `inv_warehouses`
--
ALTER TABLE `inv_warehouses`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `logs_creation`
--
ALTER TABLE `logs_creation`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `logs_deletion`
--
ALTER TABLE `logs_deletion`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `logs_statuses`
--
ALTER TABLE `logs_statuses`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `logs_update`
--
ALTER TABLE `logs_update`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `payment_gateways`
--
ALTER TABLE `payment_gateways`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `slug_UN` (`slug`);

--
-- Indices de la tabla `payment_gateways_has_countries_currencies`
--
ALTER TABLE `payment_gateways_has_countries_currencies`
  ADD PRIMARY KEY (`id`),
  ADD KEY `payment_gateway` (`payment_gateway_id`),
  ADD KEY `country_currency` (`country_currency_id`);

--
-- Indices de la tabla `payment_gateways_links`
--
ALTER TABLE `payment_gateways_links`
  ADD PRIMARY KEY (`id`),
  ADD KEY `payment_gateway` (`payment_gateway_id`);

--
-- Indices de la tabla `payment_gateway_has_clients_credentials`
--
ALTER TABLE `payment_gateway_has_clients_credentials`
  ADD PRIMARY KEY (`id`),
  ADD KEY `payment_gateway` (`payment_gateway_id`),
  ADD KEY `client` (`client_id`);

--
-- Indices de la tabla `payment_gateway_webhooks`
--
ALTER TABLE `payment_gateway_webhooks`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `webhook_id_UN` (`id_webhook`),
  ADD KEY `client` (`client_id`),
  ADD KEY `payment_gateway` (`payment_gateway_id`);

--
-- Indices de la tabla `prj_actions`
--
ALTER TABLE `prj_actions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `goal` (`id_goal`),
  ADD KEY `parent` (`id_parent`);

--
-- Indices de la tabla `prj_goals`
--
ALTER TABLE `prj_goals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `project` (`id_project`);

--
-- Indices de la tabla `prj_projects`
--
ALTER TABLE `prj_projects`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `company` (`id_company`),
  ADD KEY `type` (`id_type`),
  ADD KEY `subtype` (`id_subtype`);

--
-- Indices de la tabla `prj_projects_has_accounts`
--
ALTER TABLE `prj_projects_has_accounts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `project_account_role` (`id_project`,`id_account`,`id_role`),
  ADD KEY `project` (`id_project`),
  ADD KEY `account` (`id_account`),
  ADD KEY `role` (`id_role`);

--
-- Indices de la tabla `prj_project_sub_types`
--
ALTER TABLE `prj_project_sub_types`
  ADD PRIMARY KEY (`id`),
  ADD KEY `type` (`id_type`);

--
-- Indices de la tabla `prj_project_types`
--
ALTER TABLE `prj_project_types`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `prj_socializations`
--
ALTER TABLE `prj_socializations`
  ADD PRIMARY KEY (`id`),
  ADD KEY `project_account` (`id_project_account`),
  ADD KEY `project` (`id_project`),
  ADD KEY `goal` (`id_goal`),
  ADD KEY `action` (`id_action`),
  ADD KEY `parent` (`id_parent`);

--
-- Indices de la tabla `prj_supports`
--
ALTER TABLE `prj_supports`
  ADD PRIMARY KEY (`id`),
  ADD KEY `project` (`id_project`),
  ADD KEY `goal` (`id_goal`),
  ADD KEY `action` (`id_action`);

--
-- Indices de la tabla `sup_accounts_has_employee`
--
ALTER TABLE `sup_accounts_has_employee`
  ADD PRIMARY KEY (`id`),
  ADD KEY `account` (`id_account`),
  ADD KEY `employee` (`id_employee`);

--
-- Indices de la tabla `sup_externals`
--
ALTER TABLE `sup_externals`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `external_email` (`email`);

--
-- Indices de la tabla `sup_faq`
--
ALTER TABLE `sup_faq`
  ADD PRIMARY KEY (`id`),
  ADD KEY `page` (`id_page`),
  ADD KEY `item` (`id_item`);

--
-- Indices de la tabla `sup_pqrs`
--
ALTER TABLE `sup_pqrs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ticket` (`id_ticket`);

--
-- Indices de la tabla `sup_responses`
--
ALTER TABLE `sup_responses`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ticket` (`id_ticket`),
  ADD KEY `created_by` (`created_by`);

--
-- Indices de la tabla `sup_tickets`
--
ALTER TABLE `sup_tickets`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `subject` (`subject`),
  ADD KEY `creator_ticket` (`id_account`),
  ADD KEY `employee_support` (`id_asignee`),
  ADD KEY `external` (`id_external`),
  ADD KEY `type` (`id_type`),
  ADD KEY `sup_tickets_ibfk_pqrs` (`id_pqrs`);

--
-- Indices de la tabla `sup_tickets_assets`
--
ALTER TABLE `sup_tickets_assets`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ticket` (`id_ticket`);

--
-- Indices de la tabla `sup_tickets_types`
--
ALTER TABLE `sup_tickets_types`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `usr_accesses`
--
ALTER TABLE `usr_accesses`
  ADD PRIMARY KEY (`id`),
  ADD KEY `account` (`account_id`);

--
-- Indices de la tabla `usr_accounts`
--
ALTER TABLE `usr_accounts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email_UN` (`email`),
  ADD UNIQUE KEY `account_code_UN` (`internal_code`),
  ADD KEY `rol` (`rol_id`),
  ADD KEY `user` (`user_id`),
  ADD KEY `dial_code` (`dial_code_id`),
  ADD KEY `employee` (`employee_id`) USING BTREE;

--
-- Indices de la tabla `usr_accounts_has_scopes`
--
ALTER TABLE `usr_accounts_has_scopes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `account` (`account_id`);

--
-- Indices de la tabla `usr_employees`
--
ALTER TABLE `usr_employees`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `document_number` (`document`),
  ADD KEY `country_birth` (`id_country`),
  ADD KEY `city_residence` (`id_city`),
  ADD KEY `identification_type` (`id_identification_type`);

--
-- Indices de la tabla `usr_images`
--
ALTER TABLE `usr_images`
  ADD PRIMARY KEY (`id`),
  ADD KEY `account` (`id_account`);

--
-- Indices de la tabla `usr_preferences`
--
ALTER TABLE `usr_preferences`
  ADD PRIMARY KEY (`id`),
  ADD KEY `account` (`id_account`),
  ADD KEY `language` (`id_language`),
  ADD KEY `timezone` (`id_timezone`);

--
-- Indices de la tabla `usr_tokens`
--
ALTER TABLE `usr_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `token_id_UN` (`id_token`),
  ADD KEY `account` (`account_id`) USING BTREE;

--
-- Indices de la tabla `usr_users`
--
ALTER TABLE `usr_users`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `ai_assistants`
--
ALTER TABLE `ai_assistants`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Autonumerical identifier for each AI assistant.';

--
-- AUTO_INCREMENT de la tabla `cli_branches`
--
ALTER TABLE `cli_branches`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each company branch.';

--
-- AUTO_INCREMENT de la tabla `cli_companies`
--
ALTER TABLE `cli_companies`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each client company.', AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `cli_contacts`
--
ALTER TABLE `cli_contacts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each contact.';

--
-- AUTO_INCREMENT de la tabla `cli_departments`
--
ALTER TABLE `cli_departments`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each department.';

--
-- AUTO_INCREMENT de la tabla `cli_social_networks`
--
ALTER TABLE `cli_social_networks`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each of the company''s social networks.';

--
-- AUTO_INCREMENT de la tabla `config_endpoints`
--
ALTER TABLE `config_endpoints`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key to identify each endpoint.', AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT de la tabla `config_endpoints_has_required_scopes`
--
ALTER TABLE `config_endpoints_has_required_scopes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each relationship between endpoint and mandatory scope.';

--
-- AUTO_INCREMENT de la tabla `config_endpoints_request_schema`
--
ALTER TABLE `config_endpoints_request_schema`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Primary key. Unique auto-incrementing identifier for each request schema parameter record', AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `config_hosts`
--
ALTER TABLE `config_hosts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each host.', AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `config_pages`
--
ALTER TABLE `config_pages`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key to identify each page.', AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT de la tabla `config_pages_endpoints_has_schemas`
--
ALTER TABLE `config_pages_endpoints_has_schemas`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Primary key, unique identifier for each page-endpoint-field relationship.', AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `config_pages_has_endpoints`
--
ALTER TABLE `config_pages_has_endpoints`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each page-endpoint relationship.', AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `config_pages_has_required_scopes`
--
ALTER TABLE `config_pages_has_required_scopes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each relationship between page and mandatory scope.';

--
-- AUTO_INCREMENT de la tabla `config_roles`
--
ALTER TABLE `config_roles`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each rol.', AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT de la tabla `config_roles_has_scopes`
--
ALTER TABLE `config_roles_has_scopes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for the relationship between role and scope.';

--
-- AUTO_INCREMENT de la tabla `config_scopes`
--
ALTER TABLE `config_scopes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each scope.';

--
-- AUTO_INCREMENT de la tabla `config_shorteners`
--
ALTER TABLE `config_shorteners`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Autonumeric identifier for each link shortener.';

--
-- AUTO_INCREMENT de la tabla `config_taxes`
--
ALTER TABLE `config_taxes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each tax configuration.';

--
-- AUTO_INCREMENT de la tabla `data_currencies`
--
ALTER TABLE `data_currencies`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each currency.', AUTO_INCREMENT=158;

--
-- AUTO_INCREMENT de la tabla `data_flags`
--
ALTER TABLE `data_flags`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each flag.', AUTO_INCREMENT=248;

--
-- AUTO_INCREMENT de la tabla `data_languages`
--
ALTER TABLE `data_languages`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each language.', AUTO_INCREMENT=185;

--
-- AUTO_INCREMENT de la tabla `data_timezones`
--
ALTER TABLE `data_timezones`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each time zone.', AUTO_INCREMENT=292;

--
-- AUTO_INCREMENT de la tabla `data_types_identification`
--
ALTER TABLE `data_types_identification`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key to identify each type of identification.';

--
-- AUTO_INCREMENT de la tabla `doc_categories`
--
ALTER TABLE `doc_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier of each type of document.';

--
-- AUTO_INCREMENT de la tabla `doc_documents`
--
ALTER TABLE `doc_documents`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each document.';

--
-- AUTO_INCREMENT de la tabla `doc_documents_access`
--
ALTER TABLE `doc_documents_access`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each access to the document.';

--
-- AUTO_INCREMENT de la tabla `doc_metadata`
--
ALTER TABLE `doc_metadata`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each metadata.';

--
-- AUTO_INCREMENT de la tabla `doc_permissions`
--
ALTER TABLE `doc_permissions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each permit.';

--
-- AUTO_INCREMENT de la tabla `doc_supervisors`
--
ALTER TABLE `doc_supervisors`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each controller.';

--
-- AUTO_INCREMENT de la tabla `doc_versions`
--
ALTER TABLE `doc_versions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each version of the document.';

--
-- AUTO_INCREMENT de la tabla `doc_versions_socializations`
--
ALTER TABLE `doc_versions_socializations`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each message.';

--
-- AUTO_INCREMENT de la tabla `fin_budgets`
--
ALTER TABLE `fin_budgets`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique budget identifier.';

--
-- AUTO_INCREMENT de la tabla `fin_cashboxes`
--
ALTER TABLE `fin_cashboxes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier of the petty cash register.';

--
-- AUTO_INCREMENT de la tabla `fin_invoices`
--
ALTER TABLE `fin_invoices`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for invoice.';

--
-- AUTO_INCREMENT de la tabla `fin_invoices_details`
--
ALTER TABLE `fin_invoices_details`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each invoice detail.';

--
-- AUTO_INCREMENT de la tabla `fin_ledger_accounts`
--
ALTER TABLE `fin_ledger_accounts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier of the accounting account.';

--
-- AUTO_INCREMENT de la tabla `fin_transactions`
--
ALTER TABLE `fin_transactions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier of the transaction.';

--
-- AUTO_INCREMENT de la tabla `geo_cities`
--
ALTER TABLE `geo_cities`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each city.';

--
-- AUTO_INCREMENT de la tabla `geo_continents`
--
ALTER TABLE `geo_continents`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each continent.', AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `geo_countries`
--
ALTER TABLE `geo_countries`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each country.', AUTO_INCREMENT=248;

--
-- AUTO_INCREMENT de la tabla `geo_countries_has_currencies`
--
ALTER TABLE `geo_countries_has_currencies`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each country/currency relationship.', AUTO_INCREMENT=248;

--
-- AUTO_INCREMENT de la tabla `geo_countries_has_languages`
--
ALTER TABLE `geo_countries_has_languages`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each country/language relationship.', AUTO_INCREMENT=444;

--
-- AUTO_INCREMENT de la tabla `geo_dial_codes`
--
ALTER TABLE `geo_dial_codes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each dialing code.', AUTO_INCREMENT=248;

--
-- AUTO_INCREMENT de la tabla `geo_regions`
--
ALTER TABLE `geo_regions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each region.', AUTO_INCREMENT=26;

--
-- AUTO_INCREMENT de la tabla `geo_sub_divisions`
--
ALTER TABLE `geo_sub_divisions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each political subdivision.', AUTO_INCREMENT=142;

--
-- AUTO_INCREMENT de la tabla `hr_contracts`
--
ALTER TABLE `hr_contracts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each employment contract.';

--
-- AUTO_INCREMENT de la tabla `inv_categories`
--
ALTER TABLE `inv_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique category identifier.';

--
-- AUTO_INCREMENT de la tabla `inv_company_assets`
--
ALTER TABLE `inv_company_assets`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each asset.';

--
-- AUTO_INCREMENT de la tabla `inv_contracts_has_assets`
--
ALTER TABLE `inv_contracts_has_assets`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each employee-asset relationship.';

--
-- AUTO_INCREMENT de la tabla `inv_contracts_has_items`
--
ALTER TABLE `inv_contracts_has_items`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each relationship.';

--
-- AUTO_INCREMENT de la tabla `inv_details`
--
ALTER TABLE `inv_details`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for the item or asset detail';

--
-- AUTO_INCREMENT de la tabla `inv_inventories`
--
ALTER TABLE `inv_inventories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each inventory.';

--
-- AUTO_INCREMENT de la tabla `inv_inventories_details`
--
ALTER TABLE `inv_inventories_details`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each item in an inventory.';

--
-- AUTO_INCREMENT de la tabla `inv_inventories_states`
--
ALTER TABLE `inv_inventories_states`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each state.';

--
-- AUTO_INCREMENT de la tabla `inv_items`
--
ALTER TABLE `inv_items`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique item identifier.';

--
-- AUTO_INCREMENT de la tabla `inv_items_overrides`
--
ALTER TABLE `inv_items_overrides`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each overwrite.';

--
-- AUTO_INCREMENT de la tabla `inv_movements`
--
ALTER TABLE `inv_movements`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for the movement.';

--
-- AUTO_INCREMENT de la tabla `inv_movements_types`
--
ALTER TABLE `inv_movements_types`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each type of movement.';

--
-- AUTO_INCREMENT de la tabla `inv_types_categories`
--
ALTER TABLE `inv_types_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique type identifier.';

--
-- AUTO_INCREMENT de la tabla `inv_warehouses`
--
ALTER TABLE `inv_warehouses`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique warehouse identifier.';

--
-- AUTO_INCREMENT de la tabla `logs_creation`
--
ALTER TABLE `logs_creation`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key to identify each creation log.', AUTO_INCREMENT=22;

--
-- AUTO_INCREMENT de la tabla `logs_deletion`
--
ALTER TABLE `logs_deletion`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key to identify each deletion log.';

--
-- AUTO_INCREMENT de la tabla `logs_statuses`
--
ALTER TABLE `logs_statuses`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each log.', AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `logs_update`
--
ALTER TABLE `logs_update`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key to identify each update log.', AUTO_INCREMENT=25;

--
-- AUTO_INCREMENT de la tabla `payment_gateways`
--
ALTER TABLE `payment_gateways`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier of each payment gateway', AUTO_INCREMENT=37;

--
-- AUTO_INCREMENT de la tabla `payment_gateways_has_countries_currencies`
--
ALTER TABLE `payment_gateways_has_countries_currencies`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each relationship between payment gateway, country, and currency.';

--
-- AUTO_INCREMENT de la tabla `payment_gateways_links`
--
ALTER TABLE `payment_gateways_links`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier of each link belonging to a payment gateway.';

--
-- AUTO_INCREMENT de la tabla `payment_gateway_has_clients_credentials`
--
ALTER TABLE `payment_gateway_has_clients_credentials`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each credential.';

--
-- AUTO_INCREMENT de la tabla `payment_gateway_webhooks`
--
ALTER TABLE `payment_gateway_webhooks`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each webhook.';

--
-- AUTO_INCREMENT de la tabla `prj_actions`
--
ALTER TABLE `prj_actions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each action.';

--
-- AUTO_INCREMENT de la tabla `prj_goals`
--
ALTER TABLE `prj_goals`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each goal.';

--
-- AUTO_INCREMENT de la tabla `prj_projects`
--
ALTER TABLE `prj_projects`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each project.';

--
-- AUTO_INCREMENT de la tabla `prj_projects_has_accounts`
--
ALTER TABLE `prj_projects_has_accounts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each relationship between projects and actors.';

--
-- AUTO_INCREMENT de la tabla `prj_project_sub_types`
--
ALTER TABLE `prj_project_sub_types`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each project subtype.';

--
-- AUTO_INCREMENT de la tabla `prj_project_types`
--
ALTER TABLE `prj_project_types`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each project type.';

--
-- AUTO_INCREMENT de la tabla `prj_socializations`
--
ALTER TABLE `prj_socializations`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each socialization.';

--
-- AUTO_INCREMENT de la tabla `prj_supports`
--
ALTER TABLE `prj_supports`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each project support.';

--
-- AUTO_INCREMENT de la tabla `sup_accounts_has_employee`
--
ALTER TABLE `sup_accounts_has_employee`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each account-support employee relationship.';

--
-- AUTO_INCREMENT de la tabla `sup_faq`
--
ALTER TABLE `sup_faq`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each FAQ.';

--
-- AUTO_INCREMENT de la tabla `sup_pqrs`
--
ALTER TABLE `sup_pqrs`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each PQRS request.';

--
-- AUTO_INCREMENT de la tabla `sup_responses`
--
ALTER TABLE `sup_responses`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each response.';

--
-- AUTO_INCREMENT de la tabla `sup_tickets`
--
ALTER TABLE `sup_tickets`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each ticket.';

--
-- AUTO_INCREMENT de la tabla `sup_tickets_assets`
--
ALTER TABLE `sup_tickets_assets`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each asset.';

--
-- AUTO_INCREMENT de la tabla `sup_tickets_types`
--
ALTER TABLE `sup_tickets_types`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key to identify each available ticket type.';

--
-- AUTO_INCREMENT de la tabla `usr_accesses`
--
ALTER TABLE `usr_accesses`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each access.';

--
-- AUTO_INCREMENT de la tabla `usr_accounts`
--
ALTER TABLE `usr_accounts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each account belonging to a user.', AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `usr_accounts_has_scopes`
--
ALTER TABLE `usr_accounts_has_scopes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each relationship between an account and a scope.';

--
-- AUTO_INCREMENT de la tabla `usr_employees`
--
ALTER TABLE `usr_employees`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each user.';

--
-- AUTO_INCREMENT de la tabla `usr_images`
--
ALTER TABLE `usr_images`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier for each image.';

--
-- AUTO_INCREMENT de la tabla `usr_preferences`
--
ALTER TABLE `usr_preferences`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each created preference.', AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `usr_tokens`
--
ALTER TABLE `usr_tokens`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique primary key for identifying each created token.', AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `usr_users`
--
ALTER TABLE `usr_users`
  MODIFY `id` int NOT NULL AUTO_INCREMENT COMMENT 'Unique identifier of each client.', AUTO_INCREMENT=2;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `cli_companies`
--
ALTER TABLE `cli_companies`
  ADD CONSTRAINT `cli_companies_ibfk_1` FOREIGN KEY (`country_id`) REFERENCES `geo_countries` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `cli_companies_ibfk_2` FOREIGN KEY (`city_id`) REFERENCES `geo_cities` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `cli_social_networks`
--
ALTER TABLE `cli_social_networks`
  ADD CONSTRAINT `cli_social_networks_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `cli_companies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `config_endpoints_request_schema`
--
ALTER TABLE `config_endpoints_request_schema`
  ADD CONSTRAINT `config_endpoints_request_schema_ibfk_1` FOREIGN KEY (`endpoint_id`) REFERENCES `config_endpoints` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `config_endpoints_request_schema_ibfk_2` FOREIGN KEY (`field_id`) REFERENCES `config_endpoints_request_schema` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `config_hosts`
--
ALTER TABLE `config_hosts`
  ADD CONSTRAINT `config_hosts_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `cli_companies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `config_pages`
--
ALTER TABLE `config_pages`
  ADD CONSTRAINT `config_pages_ibfk_1` FOREIGN KEY (`page_id`) REFERENCES `config_pages` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `config_pages_ibfk_2` FOREIGN KEY (`host_id`) REFERENCES `config_hosts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `config_pages_endpoints_has_schemas`
--
ALTER TABLE `config_pages_endpoints_has_schemas`
  ADD CONSTRAINT `config_pages_endpoints_has_schemas_ibfk_1` FOREIGN KEY (`id_page_endpoint`) REFERENCES `config_pages_has_endpoints` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `config_pages_endpoints_has_schemas_ibfk_2` FOREIGN KEY (`id_endpoint_field`) REFERENCES `config_endpoints_request_schema` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `config_pages_has_endpoints`
--
ALTER TABLE `config_pages_has_endpoints`
  ADD CONSTRAINT `config_pages_has_endpoints_ibfk_1` FOREIGN KEY (`id_page`) REFERENCES `config_pages` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `config_pages_has_endpoints_ibfk_2` FOREIGN KEY (`id_endpoint`) REFERENCES `config_endpoints` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `config_taxes`
--
ALTER TABLE `config_taxes`
  ADD CONSTRAINT `config_taxes_fk_city` FOREIGN KEY (`id_city`) REFERENCES `geo_cities` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `config_taxes_fk_country` FOREIGN KEY (`id_country`) REFERENCES `geo_countries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `config_taxes_fk_sub_division` FOREIGN KEY (`id_sub_division`) REFERENCES `geo_sub_divisions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `data_languages`
--
ALTER TABLE `data_languages`
  ADD CONSTRAINT `data_languages_ibfk_1` FOREIGN KEY (`id_flag`) REFERENCES `data_flags` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `data_timezones`
--
ALTER TABLE `data_timezones`
  ADD CONSTRAINT `data_timezones_ibfk_1` FOREIGN KEY (`id_continent`) REFERENCES `geo_continents` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `data_types_identification`
--
ALTER TABLE `data_types_identification`
  ADD CONSTRAINT `data_types_identification_ibfk_1` FOREIGN KEY (`id_country`) REFERENCES `geo_countries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `doc_documents`
--
ALTER TABLE `doc_documents`
  ADD CONSTRAINT `doc_documents_ibfk_1` FOREIGN KEY (`id_category`) REFERENCES `doc_categories` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `doc_documents_access`
--
ALTER TABLE `doc_documents_access`
  ADD CONSTRAINT `doc_documents_access_ibfk_1` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `doc_documents_access_ibfk_2` FOREIGN KEY (`id_document`) REFERENCES `doc_documents` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `doc_metadata`
--
ALTER TABLE `doc_metadata`
  ADD CONSTRAINT `doc_metadata_ibfk_1` FOREIGN KEY (`id_document`) REFERENCES `doc_documents` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `doc_permissions`
--
ALTER TABLE `doc_permissions`
  ADD CONSTRAINT `doc_permissions_ibfk_1` FOREIGN KEY (`id_document`) REFERENCES `doc_documents` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `doc_permissions_ibfk_2` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `doc_permissions_ibfk_3` FOREIGN KEY (`id_role`) REFERENCES `config_roles` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `doc_permissions_ibfk_4` FOREIGN KEY (`id_supervisor`) REFERENCES `doc_supervisors` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `doc_versions`
--
ALTER TABLE `doc_versions`
  ADD CONSTRAINT `doc_versions_ibfk_1` FOREIGN KEY (`id_document`) REFERENCES `doc_documents` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `doc_versions_ibfk_2` FOREIGN KEY (`id_creator`) REFERENCES `usr_employees` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `doc_versions_socializations`
--
ALTER TABLE `doc_versions_socializations`
  ADD CONSTRAINT `doc_versions_socializations_ibfk_1` FOREIGN KEY (`id_version`) REFERENCES `doc_versions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `doc_versions_socializations_ibfk_2` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `doc_versions_socializations_ibfk_3` FOREIGN KEY (`id_supervisor`) REFERENCES `doc_supervisors` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `doc_versions_socializations_ibfk_4` FOREIGN KEY (`id_socialization`) REFERENCES `doc_versions_socializations` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `fin_budgets`
--
ALTER TABLE `fin_budgets`
  ADD CONSTRAINT `fin_budgets_ibfk_1` FOREIGN KEY (`id_project`) REFERENCES `prj_projects` (`id`) ON DELETE SET NULL ON UPDATE SET NULL;

--
-- Filtros para la tabla `fin_cashboxes`
--
ALTER TABLE `fin_cashboxes`
  ADD CONSTRAINT `fin_cashboxes_ibfk_1` FOREIGN KEY (`id_contract`) REFERENCES `usr_employees` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `fin_cashboxes_ibfk_2` FOREIGN KEY (`id_project`) REFERENCES `prj_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `fin_invoices`
--
ALTER TABLE `fin_invoices`
  ADD CONSTRAINT `fin_invoices_ibfk_1` FOREIGN KEY (`id_item`) REFERENCES `inv_items` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `fin_invoices_ibfk_2` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `fin_invoices_details`
--
ALTER TABLE `fin_invoices_details`
  ADD CONSTRAINT `fin_invoices_details_ibfk_1` FOREIGN KEY (`id_invoice`) REFERENCES `fin_invoices` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `fin_ledger_accounts`
--
ALTER TABLE `fin_ledger_accounts`
  ADD CONSTRAINT `fin_ledger_accounts_ibfk_1` FOREIGN KEY (`id_parent`) REFERENCES `fin_ledger_accounts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `fin_transactions`
--
ALTER TABLE `fin_transactions`
  ADD CONSTRAINT `fin_transactions_ibfk_1` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `fin_transactions_ibfk_2` FOREIGN KEY (`id_ledger_account`) REFERENCES `fin_ledger_accounts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `geo_cities`
--
ALTER TABLE `geo_cities`
  ADD CONSTRAINT `geo_cities_ibfk_1` FOREIGN KEY (`id_sub_division`) REFERENCES `geo_sub_divisions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `geo_cities_ibfk_2` FOREIGN KEY (`id_timezone`) REFERENCES `data_timezones` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `geo_countries`
--
ALTER TABLE `geo_countries`
  ADD CONSTRAINT `geo_countries_ibfk_3` FOREIGN KEY (`id_region`) REFERENCES `geo_regions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `geo_countries_ibfk_4` FOREIGN KEY (`id_flag`) REFERENCES `data_flags` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `geo_countries_ibfk_5` FOREIGN KEY (`id_capital`) REFERENCES `geo_cities` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `geo_countries_has_currencies`
--
ALTER TABLE `geo_countries_has_currencies`
  ADD CONSTRAINT `geo_countries_has_currencies_ibfk_1` FOREIGN KEY (`country_id`) REFERENCES `geo_countries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `geo_countries_has_currencies_ibfk_2` FOREIGN KEY (`currency_id`) REFERENCES `data_currencies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `geo_countries_has_languages`
--
ALTER TABLE `geo_countries_has_languages`
  ADD CONSTRAINT `geo_countries_has_languages_ibfk_1` FOREIGN KEY (`id_country`) REFERENCES `geo_countries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `geo_countries_has_languages_ibfk_2` FOREIGN KEY (`id_language`) REFERENCES `data_languages` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `geo_dial_codes`
--
ALTER TABLE `geo_dial_codes`
  ADD CONSTRAINT `geo_dial_codes_ibfk_1` FOREIGN KEY (`id_country`) REFERENCES `geo_countries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `geo_regions`
--
ALTER TABLE `geo_regions`
  ADD CONSTRAINT `geo_regions_ibfk_1` FOREIGN KEY (`id_continent`) REFERENCES `geo_continents` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `geo_sub_divisions`
--
ALTER TABLE `geo_sub_divisions`
  ADD CONSTRAINT `geo_sub_divisions_ibfk_1` FOREIGN KEY (`id_country`) REFERENCES `geo_countries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `geo_sub_divisions_ibfk_2` FOREIGN KEY (`id_capital`) REFERENCES `geo_cities` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `inv_categories`
--
ALTER TABLE `inv_categories`
  ADD CONSTRAINT `inv_categories_ibfk_1` FOREIGN KEY (`id_type`) REFERENCES `inv_types_categories` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `inv_company_assets`
--
ALTER TABLE `inv_company_assets`
  ADD CONSTRAINT `inv_company_assets_ibfk_1` FOREIGN KEY (`id_contract`) REFERENCES `hr_contracts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `inv_contracts_has_assets`
--
ALTER TABLE `inv_contracts_has_assets`
  ADD CONSTRAINT `inv_contracts_has_assets_ibfk_1` FOREIGN KEY (`id_asset`) REFERENCES `inv_company_assets` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_contracts_has_assets_ibfk_2` FOREIGN KEY (`id_contract`) REFERENCES `hr_contracts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `inv_contracts_has_items`
--
ALTER TABLE `inv_contracts_has_items`
  ADD CONSTRAINT `inv_contracts_has_items_ibfk_1` FOREIGN KEY (`id_contract`) REFERENCES `hr_contracts` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_contracts_has_items_ibfk_2` FOREIGN KEY (`id_item`) REFERENCES `inv_items` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `inv_details`
--
ALTER TABLE `inv_details`
  ADD CONSTRAINT `inv_details_ibfk_1` FOREIGN KEY (`id_item`) REFERENCES `inv_items` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_details_ibfk_2` FOREIGN KEY (`id_asset`) REFERENCES `inv_company_assets` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `inv_inventories`
--
ALTER TABLE `inv_inventories`
  ADD CONSTRAINT `inv_inventories_ibfk_1` FOREIGN KEY (`id_branch`) REFERENCES `adm_branches` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `inv_inventories_ibfk_2` FOREIGN KEY (`id_warehouse`) REFERENCES `inv_warehouses` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_inventories_ibfk_3` FOREIGN KEY (`id_contract`) REFERENCES `hr_contracts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `inv_inventories_details`
--
ALTER TABLE `inv_inventories_details`
  ADD CONSTRAINT `inv_inventories_details_ibfk_1` FOREIGN KEY (`id_inventory`) REFERENCES `inv_inventories` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `inv_inventories_details_ibfk_2` FOREIGN KEY (`id_item`) REFERENCES `inv_items` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `inv_inventories_details_ibfk_3` FOREIGN KEY (`id_asset`) REFERENCES `inv_company_assets` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `inv_inventories_details_ibfk_4` FOREIGN KEY (`id_state`) REFERENCES `inv_inventories_states` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `inv_items`
--
ALTER TABLE `inv_items`
  ADD CONSTRAINT `inv_items_ibfk_1` FOREIGN KEY (`id_category`) REFERENCES `inv_categories` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `inv_items_overrides`
--
ALTER TABLE `inv_items_overrides`
  ADD CONSTRAINT `inv_items_overrides_ibfk_1` FOREIGN KEY (`id_item`) REFERENCES `inv_items` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `inv_movements`
--
ALTER TABLE `inv_movements`
  ADD CONSTRAINT `inv_movements_ibfk_1` FOREIGN KEY (`id_asset`) REFERENCES `inv_company_assets` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_movements_ibfk_2` FOREIGN KEY (`id_item`) REFERENCES `inv_items` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_movements_ibfk_3` FOREIGN KEY (`id_movement`) REFERENCES `inv_movements` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_movements_ibfk_4` FOREIGN KEY (`id_warehouse`) REFERENCES `inv_warehouses` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_movements_ibfk_5` FOREIGN KEY (`id_contract`) REFERENCES `hr_contracts` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `inv_movements_ibfk_6` FOREIGN KEY (`id_type`) REFERENCES `inv_movements_types` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `payment_gateways_has_countries_currencies`
--
ALTER TABLE `payment_gateways_has_countries_currencies`
  ADD CONSTRAINT `payment_gateways_has_countries_currencies_ibfk_1` FOREIGN KEY (`payment_gateway_id`) REFERENCES `payment_gateways` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `payment_gateways_has_countries_currencies_ibfk_2` FOREIGN KEY (`country_currency_id`) REFERENCES `geo_countries_has_currencies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `payment_gateway_webhooks`
--
ALTER TABLE `payment_gateway_webhooks`
  ADD CONSTRAINT `fk_webhooks_gateway` FOREIGN KEY (`client_id`) REFERENCES `payment_gateways` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `prj_actions`
--
ALTER TABLE `prj_actions`
  ADD CONSTRAINT `prj_actions_ibfk_1` FOREIGN KEY (`id_goal`) REFERENCES `prj_goals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_actions_ibfk_2` FOREIGN KEY (`id_parent`) REFERENCES `prj_actions` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `prj_projects`
--
ALTER TABLE `prj_projects`
  ADD CONSTRAINT `prj_projects_ibfk_1` FOREIGN KEY (`id_company`) REFERENCES `usr_companies` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_projects_ibfk_2` FOREIGN KEY (`id_type`) REFERENCES `prj_project_types` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_projects_ibfk_3` FOREIGN KEY (`id_subtype`) REFERENCES `prj_project_sub_types` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `prj_projects_has_accounts`
--
ALTER TABLE `prj_projects_has_accounts`
  ADD CONSTRAINT `prj_projects_has_accounts_ibfk_1` FOREIGN KEY (`id_project`) REFERENCES `prj_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_projects_has_accounts_ibfk_2` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_projects_has_accounts_ibfk_3` FOREIGN KEY (`id_role`) REFERENCES `config_roles` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `prj_project_sub_types`
--
ALTER TABLE `prj_project_sub_types`
  ADD CONSTRAINT `prj_project_sub_types_ibfk_1` FOREIGN KEY (`id_type`) REFERENCES `prj_project_types` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `prj_socializations`
--
ALTER TABLE `prj_socializations`
  ADD CONSTRAINT `prj_socializations_ibfk_1` FOREIGN KEY (`id_project_account`) REFERENCES `prj_projects_has_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_socializations_ibfk_2` FOREIGN KEY (`id_project`) REFERENCES `prj_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_socializations_ibfk_3` FOREIGN KEY (`id_goal`) REFERENCES `prj_goals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_socializations_ibfk_4` FOREIGN KEY (`id_action`) REFERENCES `prj_actions` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_socializations_ibfk_5` FOREIGN KEY (`id_parent`) REFERENCES `prj_socializations` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `prj_supports`
--
ALTER TABLE `prj_supports`
  ADD CONSTRAINT `prj_supports_ibfk_1` FOREIGN KEY (`id_project`) REFERENCES `prj_projects` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_supports_ibfk_2` FOREIGN KEY (`id_goal`) REFERENCES `prj_goals` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `prj_supports_ibfk_3` FOREIGN KEY (`id_action`) REFERENCES `prj_actions` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `sup_faq`
--
ALTER TABLE `sup_faq`
  ADD CONSTRAINT `sup_faq_ibfk_1` FOREIGN KEY (`id_page`) REFERENCES `config_pages` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `sup_faq_ibfk_2` FOREIGN KEY (`id_item`) REFERENCES `inv_items` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `sup_pqrs`
--
ALTER TABLE `sup_pqrs`
  ADD CONSTRAINT `sup_pqrs_ibfk_1` FOREIGN KEY (`id_ticket`) REFERENCES `sup_tickets` (`id`) ON DELETE SET NULL ON UPDATE SET NULL;

--
-- Filtros para la tabla `sup_responses`
--
ALTER TABLE `sup_responses`
  ADD CONSTRAINT `sup_responses_ibfk_1` FOREIGN KEY (`id_ticket`) REFERENCES `sup_tickets` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `sup_tickets`
--
ALTER TABLE `sup_tickets`
  ADD CONSTRAINT `sup_tickets_ibfk_1` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  ADD CONSTRAINT `sup_tickets_ibfk_2` FOREIGN KEY (`id_asignee`) REFERENCES `usr_accounts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `sup_tickets_ibfk_3` FOREIGN KEY (`id_external`) REFERENCES `sup_externals` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  ADD CONSTRAINT `sup_tickets_ibfk_4` FOREIGN KEY (`id_type`) REFERENCES `sup_tickets_types` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `sup_tickets_ibfk_pqrs` FOREIGN KEY (`id_pqrs`) REFERENCES `sup_pqrs` (`id`) ON DELETE SET NULL ON UPDATE SET NULL;

--
-- Filtros para la tabla `sup_tickets_assets`
--
ALTER TABLE `sup_tickets_assets`
  ADD CONSTRAINT `sup_tickets_assets_ibfk_1` FOREIGN KEY (`id_ticket`) REFERENCES `sup_tickets` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `usr_accesses`
--
ALTER TABLE `usr_accesses`
  ADD CONSTRAINT `usr_accesses_ibfk_1` FOREIGN KEY (`account_id`) REFERENCES `usr_accounts` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `usr_accounts`
--
ALTER TABLE `usr_accounts`
  ADD CONSTRAINT `usr_accounts_ibfk_1` FOREIGN KEY (`employee_id`) REFERENCES `usr_employees` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `usr_accounts_ibfk_2` FOREIGN KEY (`rol_id`) REFERENCES `config_roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `usr_accounts_ibfk_4` FOREIGN KEY (`user_id`) REFERENCES `usr_users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT `usr_accounts_ibfk_5` FOREIGN KEY (`dial_code_id`) REFERENCES `geo_dial_codes` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

--
-- Filtros para la tabla `usr_employees`
--
ALTER TABLE `usr_employees`
  ADD CONSTRAINT `usr_employees_ibfk_1` FOREIGN KEY (`id_country`) REFERENCES `geo_countries` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  ADD CONSTRAINT `usr_employees_ibfk_2` FOREIGN KEY (`id_city`) REFERENCES `geo_cities` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  ADD CONSTRAINT `usr_employees_ibfk_3` FOREIGN KEY (`id_identification_type`) REFERENCES `data_types_identification` (`id`) ON DELETE SET NULL ON UPDATE SET NULL;

--
-- Filtros para la tabla `usr_images`
--
ALTER TABLE `usr_images`
  ADD CONSTRAINT `usr_images_ibfk_1` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `usr_preferences`
--
ALTER TABLE `usr_preferences`
  ADD CONSTRAINT `usr_preferences_ibfk_1` FOREIGN KEY (`id_account`) REFERENCES `usr_accounts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `usr_preferences_ibfk_2` FOREIGN KEY (`id_timezone`) REFERENCES `data_timezones` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `usr_preferences_ibfk_3` FOREIGN KEY (`id_language`) REFERENCES `data_languages` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `usr_tokens`
--
ALTER TABLE `usr_tokens`
  ADD CONSTRAINT `usr_tokens_ibfk_1` FOREIGN KEY (`account_id`) REFERENCES `usr_accounts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

DELIMITER $$
--
-- Eventos
--
CREATE DEFINER=`root`@`%` EVENT `DeactivateUnusedPageEndpoints` ON SCHEDULE EVERY 1 DAY STARTS '2024-12-03 14:32:02' ON COMPLETION NOT PRESERVE ENABLE DO -- Call the procedure to deactivate inactive page-endpoint relationships
    CALL DeactivateInactivePageEndpoints()$$

DELIMITER ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
