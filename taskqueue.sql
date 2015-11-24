DROP DATABASE IF EXISTS task_queue;
DROP DATABASE IF EXISTS task_queue_log;
CREATE DATABASE task_queue_log;
USE task_queue_log;

DROP TABLE IF EXISTS collection;

CREATE TABLE collection (
	collection_id int UNSIGNED AUTO_INCREMENT NOT NULL,
	provider VARCHAR(30) NOT NULL,
	collection VARCHAR(30) NOT NULL,
	id_prefix VARCHAR(30) NOT NULL,
	PRIMARY KEY (collection_id),
	UNIQUE KEY (collection, provider)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO collection VALUES (0, 'brill', 'awdl', 'brill_awdl');
INSERT INTO collection VALUES (0, 'cornell', 'aco',  'cornell_aco');
INSERT INTO collection VALUES (0, 'nyu', 'aco',  'nyu_aco');

DROP TABLE IF EXISTS task_queue;
DROP TABLE IF EXISTS task_queue_log;

CREATE TABLE task_queue_log (
	collection_id int UNSIGNED NOT NULL,
	wip_id int UNSIGNED NOT NULL,
	state ENUM ('processing', 'success', 'error') NOT NULL,
--	CURRENT_TIMESTAMP doesn't work as default value for DATETIME
--	type in MySQL 5.1
	completed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		ON UPDATE CURRENT_TIMESTAMP NOT NULL,
	PRIMARY KEY (collection_id, wip_id),
	FOREIGN KEY (collection_id) REFERENCES collection(collection_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

