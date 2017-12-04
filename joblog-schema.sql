DROP DATABASE IF EXISTS task_queue;
DROP DATABASE IF EXISTS task_queue_log;
CREATE DATABASE task_queue_log;
USE task_queue_log;

DROP TABLE IF EXISTS batch;

CREATE TABLE batch (
	batch_id int UNSIGNED AUTO_INCREMENT NOT NULL,
	user_id VARCHAR(20) NOT NULL,
	cmd_line TEXT NOT NULL,
	PRIMARY KEY (batch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS job;

CREATE TABLE job (
	job_id int UNSIGNED AUTO_INCREMENT NOT NULL,
	batch_id int UNSIGNED NOT NULL,
	state ENUM ('pending', 'processing', 'success', 'error') NOT NULL,
	request TEXT NOT NULL,
	user_id VARCHAR(20) NOT NULL,
	worker_host VARCHAR(20),
	submitted TIMESTAMP NULL,
	started   TIMESTAMP NULL,
	completed TIMESTAMP NULL,
	PRIMARY KEY (job_id),
	FOREIGN KEY (batch_id) REFERENCES batch(batch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

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
	started   TIMESTAMP NULL,
	completed TIMESTAMP NULL,
	PRIMARY KEY (collection_id, wip_id),
	FOREIGN KEY (collection_id) REFERENCES collection(collection_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

