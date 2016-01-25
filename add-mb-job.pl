#!/usr/bin/env perl
#
# Script to add jobs to task queue via AMQP.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use Data::Dumper;
use DBI;
use Getopt::Std;
use JSON;
use Net::AMQP::RabbitMQ;
use Term::ANSIColor;
use Term::ReadKey;

# Command line options
# -h:  help message
# -v:  verbose
# -f:  force adding jobs to the queue
# -b:  batch mode
# -d:  add derivative creation job
# -p:  add pdf creation job
# -s:  add stitch pages job
# -a:  add job combining 3 jobs above
# -t:  add video transcoding job
# -m:  hostname for messaging server
# -r:  rstar directory
# -c:  mysql config file
# -i:  message priority

my %opt;
getopts('hvfbdpsatm:r:c:i:', \%opt);

if ($opt{h}) {
	usage();
	exit(0);
}

my $rstar_dir = $opt{r} || $ENV{RSTAR_DIR};
if (!$rstar_dir) {
	usage("You must specify rstar directory.");
	exit(1);
} elsif (! -d $rstar_dir) {
	print STDERR "Directory $rstar_dir does not exist.\n";
	exit(1);
}

if ((exists($opt{i}) && !defined($opt{i}))
	|| (defined($opt{i}) && !($opt{i} =~ /^\d+$/ && $opt{i} <= 10)))
{
	usage("Priority must be an integer in the range 0..10");
	exit(1);
}

my $priority = $opt{i} || 0;

my $host = $opt{m} || $ENV{MQHOST} || "localhost";

my $my_cnf = $opt{c} || "/content/prod/rstar/etc/my-taskqueue.cnf";

# Automatically go into batch mode if stdin isn't connected
# to tty. Useful if using script in conjunction with xargs
my $batch_mode = $opt{b} || !-t STDIN;

my $num_flags = count_flags($opt{d}, $opt{p}, $opt{s}, $opt{a}, $opt{t});

if (!$num_flags) {
	usage("You must set one of -d, -p, -s, -a, or -t");
	exit(1);
} elsif ($num_flags > 1) {
	usage("Please select only one of -d, -p, -s, or -a");
	exit(1);
}

my $op;
if ($opt{d}) {
	$op = "create-derivatives";
} elsif ($opt{p}) {
	$op = "create-pdf";
} elsif ($opt{s}) {
	$op = "stitch-pages";
} elsif ($opt{t}) {
	$op = "transcode";
} else {
	$op = "gen-all";
}

my $wip_dir = "$rstar_dir/wip/se";

my @ids = @ARGV ? @ARGV : get_dir_contents($wip_dir);

my $queue_name = "task_queue";

my $fh;

if ($batch_mode) {
	$fh = *STDERR;
} else {
	my $more = "more";
	$more .= " -R" if $^O =~ /darwin/;
	open($fh, "|$more") or die("Can't start '$more': $!");
}

print $fh "Sending ", colored($op, 'red'), " job to ",
  colored($host, 'red'), " for books: \n";
for my $id (@ids)
{
	print $fh "$id\n";
}

unless ($batch_mode)
{
	close($fh);

	my $answer = "";
	do
	{
		print STDERR "Would you like to continue? (y)es/(n)o\n";
		$answer = ReadLine(0);
		$answer =~ s/^\s+//;
		$answer =~ s/\s+$//;
	} while $answer !~ /^(y(es)?|no?)$/i;

	if ($answer =~ /^n/)
	{
		print STDERR "Exiting.\n\n";
		exit(0);
	}
}

my $mq = Net::AMQP::RabbitMQ->new();

# connect to RabbitMQ
$mq->connect(
	$host,
	{
		user     => "guest",
		password => "guest",
		timeout  => 3,
	}
);

my $prop;
$prop = $mq->get_server_properties() if $Net::AMQP::RabbitMQ::VERSION >= 1.3;
print STDERR Dumper($prop), "\n" if $prop && $opt{v};
if ($prop && !$prop->{capabilities}{consumer_priorities} && $priority)
{
	print STDERR "Priority queues not enabled in server.\n";
}

$mq->channel_open(1);

$mq->queue_declare(
	1,
	$queue_name,
	{
		auto_delete => 0,
		durable     => 1,
		exclusive   => 0,
		passive     => 0,
	},
	{'x-max-priority' => 10}
);

my $class = $opt{t} ? "video" : "book-publisher";

my $dbh = DBI->connect("DBI:mysql:;mysql_read_default_file=$my_cnf");

my ($provider, $collection) = $rstar_dir =~ /.*\/([^\/]+)\/([^\/]+)\/*$/;
my $sth = $dbh->prepare(qq{
	SELECT collection_id FROM collection
	WHERE provider = '$provider' and collection = '$collection'
}) or die $dbh->errstr;
$sth->execute;
my ($collection_id) = $sth->fetchrow_array;
if (!$collection_id)
{
	$sth = $dbh->do(qq{
		INSERT into collection (provider, collection)
		VALUES ('$provider', '$collection')
	});
	$sth->execute;
	$collection_id = $dbh->{mysql_insert_id};
}

$sth = $dbh->prepare(qq{
	SELECT state, worker_host, completed
	FROM task_queue_log
	WHERE collection_id = ? and wip_id = ? 
}) or die $dbh->errstr;

my $tql_insert = $dbh->prepare(qq{
	INSERT INTO task_queue_log
	(collection_id, wip_id, state, user_id)
	VALUES (?, ?, 'pending', ?)
});

my $tql_update = $dbh->prepare(qq{
	UPDATE task_queue_log
	SET state = 'pending', user_id = ?, started = NULL, completed = NULL
	WHERE collection_id = ? AND wip_id = ?
});

my $login = getpwuid($<);

for my $id (@ids)
{
	$sth->execute($collection_id, $id);
	my ($state, $host, $completed) = $sth->fetchrow_array;
	if ($state && !$opt{f})
	{
		print STDERR "$id is already in $state state. Skipping.\n";
		next;
	}

	my $task = {
		class       => $class,
		operation   => $op,
		identifiers => [$id],
		rstar_dir   => $rstar_dir,
		user_id     => $login,
	};

	my $json = JSON->new;
	$json->pretty;
	$json->utf8;
	my $body = $json->encode($task);

	print STDERR "Sending $body\n" if $opt{v};

	$mq->publish(
		1,
		$queue_name,
		$body,
		{
			exchange  => "",    # default exchange
			immediate => 0,
			mandatory => 0,
		},
		{
			content_type     => 'application/json',
# 			content_encoding => 'none',
# 			correlation_id   => '123',
# 			reply_to         => 'somequeue',
# 			expiration       => 60 * 1000,
# 			message_id       => 'ABC',
# 			type             => 'notmytype',
# 			user_id          => 'guest',
# 			app_id           => 'idd',
# 			delivery_mode    => 1,
			priority         => $priority,
# 			timestamp        => 1271857990,
		},
	);

	if (!$state) {
		$tql_insert->execute($collection_id, $id, $login);
	} else {
		$tql_update->execute($login, $collection_id, $id);
	}
}

$sth->finish;
$dbh->disconnect;


sub usage
{
	my $msg = shift;
	print STDERR "\n";
	print STDERR "$msg\n\n" if $msg;
	print STDERR "Usage: $0 -r <rstar dir> [-m <mq host>] \n",
		"           [-i <priority>] [ -b ] [ -d | -s | p ] [wip_id] ...\n\n",
		"        -m     <RabbitMQ host>\n",
		"        -r     <R* directory>\n",
		"        -h     flag to print help message\n",
		"        -v     verbose output\n",
		"        -b     batch mode, won't prompt user\n",
		"        -i     <message priority>\n",
		"        -d     flag to create job to generate derivatives\n",
		"        -p     flag to create job to generate pdfs\n",
		"        -s     flag to create job to stitch pages\n",
		"        -a     flag to create job combining 3 jobs above\n",
		"        -t     flag to create job to transcode videos\n";
	print STDERR "\n";
}


sub count_flags
{
	my $cnt = 0;
	for my $flag (@_)
	{
		$cnt += $flag || 0;
	}
	return $cnt;
}


sub get_dir_contents
{
	my $dir_path = shift;
	opendir(my $dirh, $dir_path) or die("can't opendir $dir_path: $!");
	my @files = sort(grep { !/^\./ } readdir($dirh));
	closedir($dirh);
	return @files;
}

