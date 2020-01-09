USE task_queue_log;

/*
CREATE TABLE output (
	job_id int UNSIGNED NOT NULL UNIQUE,
	output TEXT NOT NULL,
	FOREIGN KEY (job_id) REFERENCES job(job_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
*/

DROP TABLE IF EXISTS output;

ALTER TABLE job ADD output TEXT DEFAULT NULL AFTER state;

