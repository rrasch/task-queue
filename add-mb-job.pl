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
# -o:  operation
# -e:  extra command line args
# -j:  json config to pass to job

my %opt;
getopts('hvfbdpsatm:r:c:i:o:e:j:', \%opt);

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

my $extra_args = $opt{e} || '';

my $json_config = $opt{j} || '';

# Automatically go into batch mode if stdin isn't connected
# to tty. Useful if using script in conjunction with xargs
my $batch_mode = $opt{b} || !-t STDIN;

my $num_flags = count_flags(@opt{'d', 'p', 's', 'a', 't', 'o'});

if (!$num_flags) {
	usage("You must set one of -d, -p, -s, -a, -t, or -o");
	exit(1);
} elsif ($num_flags > 1) {
	usage("Please select only one of -d, -p, -s, -a, -t, or -o");
	exit(1);
}

my ($class, $op);
if ($opt{d}) {
	$op = "create-derivatives";
} elsif ($opt{p}) {
	$op = "create-pdf";
} elsif ($opt{s}) {
	$op = "stitch-pages";
} elsif ($opt{a}) {
	$op = "gen-all";
} elsif ($opt{t}) {
	$op = "transcode_wip";
} elsif ($opt{o}) {
	($class, $op) = split(/:/, $opt{o});
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
$mq->connect($host, {timeout => 3});

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
	},
	{'x-max-priority' => 10}
);

$class = $opt{t} ? "video" : "book-publisher" if !$class;

my $dbh = DBI->connect("DBI:mysql:;mysql_read_default_file=$my_cnf");

my ($provider, $collection) = $rstar_dir =~ /.*\/([^\/]+)\/([^\/]+)\/*$/;

my $sth = $dbh->prepare(qq{
	SELECT collection_id FROM collection
	WHERE provider = '$provider' and collection = '$collection'
}) or die $dbh->errstr;
$sth->execute;
my ($collection_id) = $sth->fetchrow_array;

$sth = $dbh->prepare(qq{
	SELECT state
	FROM task_queue_log
	WHERE collection_id = ? and wip_id = ? 
}) or die $dbh->errstr;

my $login = getpwuid($<);

my $task = {
	class       => $class,
	operation   => $op,
	rstar_dir   => $rstar_dir,
	user_id     => $login,
	state       => 'pending',
};

my $json = JSON->new;
$json->pretty;
$json->utf8;

if ($json_config)
{
	my $json_str = read_file($json_config);
	my $cfg = $json->decode($json_str);
	while (my ($k, $v) = each %$cfg)
	{
		$task->{$k} = $v;
	}
}

for my $id (@ids)
{
	my ($state);

	if ($collection_id)
	{
		$sth->execute($collection_id, $id);
		($state) = $sth->fetchrow_array;
	}

	if ($state && !$opt{f})
	{
		print STDERR "$id is already in $state state. Skipping.\n";
		next;
	}

	$task->{identifiers} = [$id];

	my $body = $json->encode($task);

	print STDERR "Sending $body\n" if $opt{v};

	$mq->publish(1, "$queue_name.pending", $body,
		{exchange => 'tq_logging'});

	$mq->publish(1, $queue_name, $body, {},
		{priority => $priority});
}

$sth->finish;
$dbh->disconnect;


sub usage
{
	my $msg = shift;
	print STDERR "\n";
	print STDERR "$msg\n\n" if $msg;
	print STDERR "Usage: $0 -r <rstar dir> [-m <mq host>]\n",
		"           [-i <priority>] [-c <mysql config>]\n",
		"           [-b] [-f]  -d | -p | -s | -a | -t | -o <operation>\n",
		"           [-e <extra_args>] [-j <json config]\n",
		"           [wip_id] ...\n\n",
		"        -m     <RabbitMQ host>\n",
		"        -r     <R* directory>\n",
		"        -h     flag to print help message\n",
		"        -v     verbose output\n",
		"        -b     batch mode, won't prompt user\n",
		"        -f     force adding jobs to queue\n",
		"        -i     <message priority>\n",
		"        -c     <path to mysql config file>\n",
		"        -o     <operation>\n",
		"        -d     flag to create job to generate derivatives\n",
		"        -p     flag to create job to generate pdfs\n",
		"        -s     flag to create job to stitch pages\n",
		"        -a     flag to create job combining 3 jobs above\n",
		"        -t     flag to create job to transcode videos\n",
		"        -e     <extra command ling args>\n",
		"        -j     <json config file to pass to job>\n";
	print STDERR "\n";
}


sub count_flags
{
	my $cnt = 0;
	for my $flag (@_)
	{
		$cnt++ if $flag;
	}
	return $cnt;
}


sub read_file
{
	my $file = shift;
	local $/ = undef;
	open(my $in, $file) or die("can't open $file: $!");
	my $str = <$in>;
	close($in);
	return $str;
}


sub get_dir_contents
{
	my $dir_path = shift;
	opendir(my $dirh, $dir_path) or die("can't opendir $dir_path: $!");
	my @files = sort(grep { !/^\./ } readdir($dirh));
	closedir($dirh);
	return @files;
}

