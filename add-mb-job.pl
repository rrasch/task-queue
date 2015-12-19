#!/usr/bin/env perl
#
# Script to add jobs to task queue via AMQP.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use Getopt::Std;
use JSON;
use Net::AMQP::RabbitMQ;
use Term::ANSIColor;
use Term::ReadKey;

our $opt_v;   # verbose
our $opt_h;   # help message
our $opt_b;   # batch mode
our $opt_d;   # add derivative creation job
our $opt_p;   # add pdf creation job
our $opt_s;   # add stitch pages job
our $opt_a;   # add job combining 3 jobs above
our $opt_t;   # add video transcoding job
our $opt_m;   # hostname for messaging server
our $opt_r;   # rstar directory

getopts('hvbdpsatm:r:');

my $num_flags = count_flags($opt_d, $opt_p, $opt_s, $opt_a, $opt_t);

if ($opt_h) {
	usage();
	exit(0);
} elsif (!$num_flags) {
	usage("You must set one of -d, -p, -s, -a, or -t");
	exit(1);
} elsif ($num_flags > 1) {
	usage("Please select only one of -d, -p, -s, or -a");
	exit(1);
}

my $op;
if ($opt_d) {
	$op = "create-derivatives";
} elsif ($opt_p) {
	$op = "create-pdf";
} elsif ($opt_s) {
	$op = "stitch-pages";
} elsif ($opt_t) {
	$op = "transcode";
} else {
	$op = "gen-all";
}

my $rstar_dir  = $opt_r || $ENV{RSTAR_DIR};

if (!$rstar_dir) {
	usage("You must specify rstar directory.");
	exit(1);
} elsif (! -d $rstar_dir) {
	print STDERR "Directory $rstar_dir does not exist.\n";
	exit(1);
}

my $wip_dir = "$rstar_dir/wip/se";

my @ids = @ARGV ? @ARGV : get_dir_contents($wip_dir);

my $queue_name = "task_queue";

my $host = $opt_m || $ENV{'MQHOST'} || "localhost";

my $fh;

if ($opt_b) {
	$fh = *STDERR;
} else {
	open($fh, "|more") or die("Can't start more: $!");
}

print $fh "Sending ", colored($op, 'red'), " job to ",
  colored($host, 'red'), " for books: \n";
for my $id (@ids)
{
	print $fh "$id\n";
}

unless ($opt_b)
{
	close($fh) unless $opt_b;

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

$mq->channel_open(1);

$mq->queue_declare(
	1,
	$queue_name,
	{
		auto_delete => 0,
		durable     => 1,
		exclusive   => 0,
		passive     => 0,
	}
);

my $class = $opt_t ? "video" : "book-publisher";

for my $id (@ids)
{
	my $task = {
		class       => $class,
		operation   => $op,
		identifiers => [$id],
		rstar_dir   => $rstar_dir,
	};

	my $json = JSON->new;
	$json->pretty;
	$json->utf8;
	my $body = $json->encode($task);

	print STDERR "Sending $body\n" if $opt_v;

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
# 			priority         => 2,
# 			timestamp        => 1271857990,
		},
	);
}


sub usage
{
	my $msg = shift;
	print STDERR "\n";
	print STDERR "$msg\n\n" if $msg;
	print STDERR "Usage: $0 -r <rstar dir> [-m <mq host>] \n",
		"           [ -b ] [ -d | -s | p ] [wip_id] ...\n\n",
		"        -m     <RabbitMQ host>\n",
		"        -r     <R* directory>\n",
		"        -h     flag to print help message\n",
		"        -v     verbose output\n",
		"        -b     batch mode, won't prompt user\n",
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

