CREATE TABLE IF NOT EXISTS `billing_invoices` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `bill_type` ENUM('private','job') NOT NULL DEFAULT 'private',
  `job_name` VARCHAR(50) NULL DEFAULT NULL,
  `job_label` VARCHAR(100) NULL DEFAULT NULL,
  `number_prefix` VARCHAR(16) NOT NULL DEFAULT 'PRIV',
  `issuer_identifier` VARCHAR(80) NOT NULL,
  `issuer_name` VARCHAR(100) NOT NULL DEFAULT '',
  `target_identifier` VARCHAR(80) NOT NULL,
  `target_name` VARCHAR(100) NOT NULL DEFAULT '',
  `reason` VARCHAR(255) NOT NULL DEFAULT '',
  `subtotal` BIGINT NOT NULL DEFAULT 0,
  `tax` BIGINT NOT NULL DEFAULT 0,
  `total` BIGINT NOT NULL DEFAULT 0,
  `late_fee` BIGINT NOT NULL DEFAULT 0,
  `no_profit` TINYINT(1) NOT NULL DEFAULT 0,
  `status` ENUM('unpaid','paid','cancelled') NOT NULL DEFAULT 'unpaid',
  `paid_by` VARCHAR(80) NULL DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `paid_at` DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_target_status` (`target_identifier`, `status`),
  KEY `idx_job_status` (`job_name`, `status`),
  KEY `idx_issuer` (`issuer_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `billing_invoice_items` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `invoice_id` INT NOT NULL,
  `description` VARCHAR(120) NOT NULL,
  `quantity` INT NOT NULL DEFAULT 1,
  `unit_price` BIGINT NOT NULL DEFAULT 0,
  `line_total` BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_invoice` (`invoice_id`),
  CONSTRAINT `fk_billing_invoice_items` FOREIGN KEY (`invoice_id`) REFERENCES `billing_invoices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS `billing_price_categories` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `job_name` VARCHAR(50) NOT NULL,
  `name` VARCHAR(80) NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_price_job` (`job_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `billing_price_items` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `category_id` INT NOT NULL,
  `label` VARCHAR(120) NOT NULL,
  `short` VARCHAR(40) NOT NULL DEFAULT '',
  `price` BIGINT NOT NULL DEFAULT 0,
  `sort_order` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_price_category` (`category_id`),
  CONSTRAINT `fk_billing_price_items` FOREIGN KEY (`category_id`) REFERENCES `billing_price_categories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
