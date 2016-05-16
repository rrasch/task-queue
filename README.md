## About ##

This is a project to run a set of jobs in parallel using the RabbitMQ message broker.

## Requirements ##

- bunny gem
- chronic gem
- mediainfo gem
- mysql2 gem
- servolux gem
- Net::AMQP::RabbitMQ perl module

## Usage ##

To see a list of all available options available run the script with the '-h' help switch:

    add-mb-job -h

Here is the usage message:

    Usage: add-mb-job -r <rstar dir> [-m <mq host>]
               [-p <priority>] [-c <mysql config>]
               -s <service>
               [-e <extra_args>] [-j <json config>]
               [wip_id] ...
    
            -m     <RabbitMQ host>
            -r     <R* directory>
            -h     flag to print help message
            -v     verbose output
            -i     <message priority>
            -c     <path to mysql config file>
            -s     <service>
            -e     <extra command ling args>
            -j     <json config file to pass to job>

## Derivative Generation ##

To add jobs to the task queue, run the 'add-mb-job.pl' script.  For example, to generate derivatives for the book 'cornell_aco000384' from the Cornell ACO collection, the invocation would look like:

    add-mb-job -m localhost \
        -r /root/path/of/rstar/content/cornell/aco \
        -s  book_publisher:create_derivatives \
        cornell_aco000384

Here the '-r' option sets the path to the rstar directory, '-m' specifies the hostname of RabbitMQ message broker, and the 's' flag sets the service to "book_publisher:create_derivatives" which tells the workers to generate derivatives for the book.

To generate derivatives, pdf, and stitched pages for a book, simply change the -s to 'book_publisher:gen_all'

    add-mb-job -m localhost \
        -r /root/path/of/rstar/content/cornell/aco \
        -s book_publisher:gen_all \
        cornell_aco000384

If you would like to process all wip ids in the rstar directory, do no specify any wip ids on the command line.

    add-mb-job -m localhost \
        -r /root/path/of/rstar/content/cornell/aco \
        -s book_publisher:gen_all

If you have a file containing a list of wip ids you could do the following:

    cat wip_id_list.txt | xargs add-mb-job \
        -r /root/path/of/rstar/content/cornell/aco \
        -s book_publisher:gen_all

OR

    add-mb-job \
        -r /root/path/of/rstar/content/cornell/aco \
        -s book_publisher:gen_all `cat wip_id_list.txt`

Possible service values for book publishing are:

    book_publisher:stitch_pages
    book_publisher:create_pdf
    book_publisher:create_ocr
    book_publisher:create_map
    book_publisher:gen_all

## Audio/Video Encoding ##

To transcode videos in a wip structure, you would use an invocation similar to above but would change the service to "video:transcode_wip".  For example:

    add-mb-job -m localhost \
        -r /root/path/of/rstar/provider/collection \
        -s  video:transcode_wip \
        wip_id

To transcode videos from an input directory and place the newly encoded files in an output directory, change the service to "transcode_dir"

    add-mb-job -m localhost \
        -i /input/directory \
        -o /output/directory \
        -s  video:transcode_dir

To encode audio files:

    add-mb-job -m localhost \
        -i /input/directory \
        -o /output/directory \
        -s  audio:transcode_dir

## Additional Options ##

Sending jobs to the task-queue causes the backends scripts to run with their default options.  For example, transcoding runs with the "Movie Scenes" encoding profile.  At present, there are two ways to change this behavior.  You can set the -e flag to pass in extra arguments or you create a text file containing a json hash which sets the key "extra_args".  Let's say we want to change the encoding profile to "HIDVL"

Method 1:

    add-mb-job -m localhost \
        -i /input/directory \
        -o /output/directory \
        -s  video:transcode_dir \
        -e "--profile hidvl"
 
Method 2:

    echo '{"extra_args": "--profile hidvl"}' > config.json
    add-mb-job -m localhost \
        -i /input/directory \
        -o /output/directory \
        -s  video:transcode_dir \
        -j config.json
 
## JSON Configuration ##

In the above example, you saw how we set extra_args using a json file to change the default profile for video encoding.  You can use it to also set different parameters for the backend class.  You can find more examples in the doc directory.

# Job Status ##

You will notice that once a job is submitted, you will receive a batch number which you can use to track all jobs within a batch.  This is probably more useful when submitting rstar related jobs because you might have multiple wip ids in a batch.

Once you've added jobs to the queue, you'll probably want to check their status.  This can be accomplished by running the following script:

    check-job-status

This will produce a simple table that shows the wip id, job status (such as 'processing', 'success', 'error'), and date of completion.

To check the status of jobs in a particular batch, please add the batch number to the -b switch.  For example to check the status of batch 3:

    check-job-status -b 3

You can see the list of available options by specifying the '--help' flag.

