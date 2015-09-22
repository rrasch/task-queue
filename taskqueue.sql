DROP DATABASE IF EXISTS task_queue;
DROP DATABASE IF EXISTS task_queue_log;
CREATE DATABASE task_queue_log;
USE task_queue_log;

DROP TABLE IF EXISTS collection;

CREATE TABLE collection (
	collection_id int UNSIGNED AUTO_INCREMENT NOT NULL,
	provider VARCHAR(30) NOT NULL,
	collection VARCHAR(30) NOT NULL,
	PRIMARY KEY (collection_id),
	UNIQUE KEY (collection, provider)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO collection VALUES (0, 'nyu', 'aco');
INSERT INTO collection VALUES (0, 'cornell', 'aco');

DROP TABLE IF EXISTS task_queue;
DROP TABLE IF EXISTS task_queue_log;

CREATE TABLE task_queue_log (
	collection_id int UNSIGNED NOT NULL,
	wip_id int UNSIGNED NOT NULL,
	state ENUM ('processing', 'success', 'error') NOT NULL,
	completed DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (collection_id, wip_id),
	FOREIGN KEY (collection_id) REFERENCES collection(collection_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

