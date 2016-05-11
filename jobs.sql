USE task_queue_log;

DROP TABLE IF EXISTS batch;

CREATE TABLE batch (
	batch_id int UNSIGNED AUTO_INCREMENT NOT NULL,
	user_id VARCHAR(20) NOT NULL,
	cmd_line VARCHAR(150) NOT NULL,
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

