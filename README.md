## About ##

This is a project to run a set of jobs in parallel using the RabbitMQ message broker.

## Requirements ##

- bunny gem
- mysql2 gem
- servolux gem
- Net::AMQP::RabbitMQ perl module

## Derivative Generation ##

In order to generate derivatives for books and image collections, please checkout the latest copy of this project:

    git clone  https://github.com/rrasch/task-queue.git
    cd task-queue

To add jobs to the task queue, run the 'add-mb-job.pl' script.  For example, to generate derivatives for the book 'cornell_aco000384' from the Cornell ACO collection, the invocation would look like:

    ./add-mb-job.pl -m localhost \
        -r /root/path/of/rstar/content/cornell/aco \
        -d cornell_aco000384

Here the '-r' option sets the path to the rstar directory, '-m' specificies the hostname of RabbitMQ message broker, and the '-d' flag tells the workers to generate derivatives for the book.

To generate derviatives, pdf, and stitched pages for a book, simply replace the '-d' switch with the '-a' flag:

    ./add-mb-job.pl -m localhost \
        -r /root/path/of/rstar/content/cornell/aco \
        -a cornell_aco000384

If you would like to process all wip ids in the rstar directory, do no specify any wip ids on the command line.

    ./add-mb-job.pl -m localhost \
        -r /root/path/of/rstar/content/cornell/aco -a

If you have a file containing a list of wip ids you could do the following:

    cat wip_id_list.txt | xargs ./add-mb-job.pl \
        -r /root/path/of/rstar/content/cornell/aco -a

To see a list of all available options available run the script with the '-h' help switch:

    ./add-mb-job.pl -h

Here is the usage message:

    Usage: ./add-mb-job.pl [-m <mq host>] [ -r <rstar dir> ] 
               [-i <priority>] [ -d | -s | -p ] [wip_id] ...

        -m     <RabbitMQ host>
        -r     <R* directory>
        -h     flag to print help message
        -v     verbose output
        -b     batch mode, won't prompt user
        -i     <message priority>  (value 0-10)
        -d     flag to create job to generate derivatives
        -p     flag to create job to generate pdfs
        -s     flag to create job to stitch pages
        -a     flag to create job combining 3 jobs above
        -t     flag to create job to transcode videos

Once you've added jobs to the queue, you'll probably want to check their status.  This can be accomplished by running the following script:

    ./check-job-status.rb

To check the status of the job above you would run:

    ./check-job-status.rb \
        -r /root/path/of/rstar/content/cornell/aco \
        cornell_aco000384

This will produce a simple table that shows the wip id, job status (such as 'processing', 'success', 'error'), and date of completion.

You can see the list of available options by specifying the '--help' flag.

