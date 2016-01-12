DROP DATABASE IF EXISTS task_queue;
DROP DATABASE IF EXISTS task_queue_log;
CREATE DATABASE task_queue_log;
USE task_queue_log;

DROP TABLE IF EXISTS job_set;

CREATE TABLE job_set (
	job_id int UNSIGNED AUTO_INCREMENT NOT NULL,
	PRIMARY KEY (job_id)
);

DROP TABLE IF EXISTS collection;

CREATE TABLE collection (
	collection_id int UNSIGNED AUTO_INCREMENT NOT NULL,
	provider VARCHAR(30) NOT NULL,
	collection VARCHAR(30) NOT NULL,
	type ENUM ('book', 'image', 'video') NOT NULL,
	PRIMARY KEY (collection_id),
	UNIQUE KEY (collection, provider)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO collection VALUES (0, 'brill',   'awdl', 'book');
INSERT INTO collection VALUES (0, 'cornell', 'aco',  'book');
INSERT INTO collection VALUES (0, 'fales',   'gcn',  'video');
INSERT INTO collection VALUES (0, 'nyu',     'aco',  'book');

DROP TABLE IF EXISTS task_queue;
DROP TABLE IF EXISTS task_queue_log;

CREATE TABLE task_queue_log (
	collection_id int UNSIGNED NOT NULL,
	wip_id VARCHAR(30) NOT NULL,
	state ENUM ('pending', 'processing', 'success', 'error') NOT NULL,
	user_id VARCHAR(20) NOT NULL,
	worker_host VARCHAR(20),
--	CURRENT_TIMESTAMP doesn't work as default value for DATETIME
--	type in MySQL 5.1
	completed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		ON UPDATE CURRENT_TIMESTAMP NOT NULL,
	PRIMARY KEY (collection_id, wip_id),
	FOREIGN KEY (collection_id) REFERENCES collection(collection_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

