#!/usr/bin/env perl
#
# Script to add jobs to task queue via AMQP.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use Cwd qw(abs_path);
use Data::Dumper;
use DBI;
use File::Basename;
use File::Spec;
use Getopt::Std;
use JSON;
use Net::AMQP::RabbitMQ;
use String::ShellQuote;
use Sys::Hostname;
use YAML::PP;

our $EXCHANGE_NAME = "tq_logging";
our $CHANNEL_MAX = 32;
our $PERSISTENT_DELIVERY_MODE = 2;

# Command line options
# -h:  help message
# -v:  verbose
# -m:  hostname for messaging server
# -r:  rstar directory
# -i:  input path (directory or file)
# -o:  output path (directory or file prefix)
# -c:  mysql config file
# -p:  message priority
# -s:  service
# -e:  extra command line args
# -j:  json config to pass to job

my $cmd_line = String::ShellQuote::shell_quote(abs_path($0), @ARGV);

my %opt;
getopts('hvtm:r:i:o:c:p:s:e:j:', \%opt);

if ($opt{h}) {
	usage();
	exit(0);
}

print "Running in test mode.\n" if $opt{t};

my $rstar_dir   = $opt{r};
my $input_path  = $opt{i};
my $output_path = $opt{o};

if ((exists($opt{p}) && !defined($opt{p}))
	|| (defined($opt{p}) && !($opt{p} =~ /^\d+$/ && $opt{p} <= 10)))
{
	usage("Priority must be an integer in the range 0..10");
	exit(1);
}

my $env = hostname() =~ /^d/ ? "dev" : "prod";

my $sys_conf_file = "/content/$env/rstar/etc/task-queue.sysconfig";

my $priority = $opt{p} || 0;

my $host = $opt{m} || get_mqhost($sys_conf_file) || "localhost";

my $my_cnf = $opt{c} || "/content/$env/rstar/etc/my-taskqueue.cnf";

my $extra_args = $opt{e} || '';

my $json_config = $opt{j} || '';

my $class;
my $op;

if (!$opt{t})
{
	my @services = get_services();

	if (!$opt{s})
	{
		usage("You must set -s to define the service.");
		exit(1);
	}

	if (!grep { $_ eq $opt{s} } @services)
	{
		usage(  "Service '$opt{s}' not allowed. "
			  . "You must set -s to one of:\n\n\t"
			  . join("\n\t", @services));
		exit(1);
	}

	($class, $op) = split(/:/, $opt{s});

	if (!$class || !$op)
	{
		usage(  "You must set -s to define service in the format "
			  . "<class>:<service>, e.g. audio:transcode");
		exit(1);
	}
}

my $task_queue_name = "task_queue";
my $hpc_queue_name = "hpc_transcode";

my $mq = Net::AMQP::RabbitMQ->new();

# connect to RabbitMQ
print STDERR "Connecting to RabbitMQ host $host\n" if $opt{v};
$mq->connect($host, {timeout => 3, channel_max => $CHANNEL_MAX});

my $prop;
$prop = $mq->get_server_properties() if $Net::AMQP::RabbitMQ::VERSION >= 1.3;
print STDERR Dumper($prop), "\n" if $prop && $opt{v};
if ($prop && !$prop->{capabilities}{consumer_priorities} && $priority)
{
	print STDERR "Priority queues not enabled in server.\n";
}

$mq->channel_open(1);

for my $qname ($task_queue_name, $hpc_queue_name)
{
	my ($name, $num_msgs, $num_consumers) = $mq->queue_declare(
		1, $qname,
		{
			auto_delete => 0,
			durable     => 1,
		},
		{'x-max-priority' => 10}
	);
	print STDERR "queue: $name, ",
	  "num msgs waiting: $num_msgs, ",
	  "num consumers: $num_consumers\n"
	  if $opt{v};
}

my $login = getpwuid($<);

my $dbh = DBI->connect("DBI:mysql:;mysql_read_default_file=$my_cnf");

exit(0) if $opt{t};

$dbh->do("
	INSERT into batch (user_id, cmd_line)
	VALUES (?, ?)", undef, $login, $cmd_line)
  or die $dbh->errstr;

my $batch_id = $dbh->{mysql_insertid};

my $insert_job = $dbh->prepare("
	INSERT INTO job
	(batch_id, state, request, user_id, submitted)
	VALUES ($batch_id, 'pending', ?, '$login', NOW())")
  or die $dbh->errstr;

my $task = {
	'class'       => $class,
	'operation'   => $op,
	'extra_args'  => $extra_args,
	'user_id'     => $login,
	'batch_id'    => $batch_id,
	'state'       => 'pending',
};

$task->{rstar_dir}   = $rstar_dir   if $rstar_dir;
$task->{input_path}  = $input_path  if $input_path;
$task->{output_path} = $output_path if $output_path;

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

if ($rstar_dir)
{
	# Create a job for each wip id
	my @ids = @ARGV ? @ARGV : get_dir_contents("$rstar_dir/wip/se");
	for my $id (@ids)
	{
		$task->{identifiers} = [$id];
		publish($task);
	}
}
else
{
	publish($task);
}

print STDERR "The batch id $batch_id\n";


sub publish
{
	my ($task) = @_;
	my $body = $json->encode($task);
	$insert_job->execute($body);
	$task->{job_id} = $dbh->{mysql_insertid};
	$body = $json->encode($task);
	delete $task->{job_id};
	print STDERR "Sending $body\n" if $opt{v};
	$mq->publish(
		1,
		"$task_queue_name.pending",
		$body,
		{exchange      => $EXCHANGE_NAME},
		{delivery_mode => $PERSISTENT_DELIVERY_MODE}
	);
	$mq->publish(
		1,
		$task_queue_name,
		$body,
		{},
		{
			priority      => $priority,
			delivery_mode => $PERSISTENT_DELIVERY_MODE
		}
	);
}


sub usage
{
	my $msg = shift;
	print STDERR "\n";
	print STDERR "$msg\n\n" if $msg;
	print STDERR "Usage: $0 -r <rstar dir> [-m <mq host>]\n",
		"           [-p <priority>] [-c <mysql config>]\n",
		"           -s <service>\n",
		"           [-e <extra_args>] [-j <json config>]\n",
		"           [wip_id] ...\n\n",
		"        -m     <RabbitMQ host>\n",
		"        -r     <R* directory>\n",
		"        -i     <input directory or file>\n",
		"        -o     <output directory or file prefix>\n",
		"        -h     flag to print help message\n",
		"        -v     verbose output\n",
		"        -t     test connection to rabbitmq and mysql\n",
		"        -p     <message priority>\n",
		"        -c     <path to mysql config file>\n",
		"        -s     <service>\n",
		"        -e     <extra command ling args>\n",
		"        -j     <json config file to pass to job>\n";
	print STDERR "\n";
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


sub get_services
{
	my $services_file =
	  File::Spec->catfile(dirname(abs_path($0)), 'services.yaml');
	my $ypp = YAML::PP->new;
	open(my $fh, '<', $services_file)
	  or die("Could not open $services_file: $!");
	my $data = $ypp->load_file($fh);
	close($fh);
	my @services = @{$data->{services}};
	return @services;
}


sub get_mqhost
{
	my ($filepath) = @_;
	my %config;

	open(my $fh, $filepath)
	  or die("Could not open '$filepath': $!");

	while (<$fh>)
	{
		chomp;
		next if /^\s*#/;
		next if /^\s*$/;
		if (/^\s*([\w\-]+)\s*=\s*["']?(.*?)["']?\s*$/)
		{
			my ($key, $value) = ($1, $2);
			$config{lc($key)} = $value;
		}
	}

	close($fh);

	return $config{"mqhost"};
}
