## About ##

This is a project to run a set of jobs in parallel using the RabbitMQ message broker.

## Requirements ##

Ruby

- bunny gem
- chronic gem
- mediainfo gem
- mysql2 gem
- servolux gem
- sql-maker gem

Python

- python3.11
- python3.12
- mysqlclient
- pika
- psutil
- tabulate
- tomli

## Usage ##

To see a list of all available options available run the script with the `--help` switch:

```bash
add-mb-job --help
```

Here is the usage message:

```
usage: add-mb-joby [-h] [-v] [-t] [-m MQHOST] [-r RSTAR_DIR]
                   [-i INPUT_PATH] [-o OUTPUT_PATH]
                   [-c MYSQL_CONFIG_FILE]
                   [-p {0,1,2,3,4,5,6,7,8,9,10}]
                   [-s {audio:fast_transcribe,
                        audio:transcode,
                        audio:transcribe,
                        bagit:validate,
                        book_publisher:create_derivatives,
                        book_publisher:create_dmakers,
                        book_publisher:create_map,
                        book_publisher:create_ocr,
                        book_publisher:create_pdf,
                        book_publisher:gen_all,
                        book_publisher:hocr2pdf,
                        book_publisher:make_yaiglobal_upload_pdf,
                        book_publisher:shrink_aco_pdf,
                        book_publisher:stitch_pages,
                        util:env,util:fortune,
                        util:nope,util:ping,
                        video:convert_iso,
                        video:transcode}]
                   [-e EXTRA_ARGS] [-j JSON_CONFIG]
                   [ID ...]

positional arguments:
  ID                    Digital object identifier

options:
  -h, --help            show this help message and exit
  -v, --verbose         Enable verbose messages
  -t, --test            Test connection to rabbitmq and mysql
  -m, --mqhost MQHOST   hostname for RabbitMQ messaging server (default: localhost)
  -r, --rstar-dir RSTAR_DIR
                        R* (Rstar) directory
  -i, --input-path INPUT_PATH
                        input path (directory or file)
  -o, --output-path OUTPUT_PATH
                        output path (directory or file prefix)
  -c, --mysql-config-file MYSQL_CONFIG_FILE
                        mysql config file (default: /content/<env>/rstar/etc/my-taskqueue.cnf)
  -p, --priority {0,1,2,3,4,5,6,7,8,9,10}
                        message priority (default: 0, lowest priority)
  -s, --service {audio:fast_transcribe,
                 audio:transcode,
                 audio:transcribe,
                 bagit:validate,
                 book_publisher:create_derivatives,
                 book_publisher:create_dmakers,
                 book_publisher:create_map,
                 book_publisher:create_ocr,
                 book_publisher:create_pdf,
                 book_publisher:gen_all,
                 book_publisher:hocr2pdf,
                 book_publisher:make_yaiglobal_upload_pdf,
                 book_publisher:shrink_aco_pdf,
                 book_publisher:stitch_pages,
                 util:env,
                 util:fortune,
                 util:nope,
                 util:ping,
                 video:convert_iso,
                 video:transcode}
                        service, e.g. video:transcode
  -e, --extra-args EXTRA_ARGS
                        extra command line args
  -j, --json-config JSON_CONFIG
                        json config to pass to job
```

The main options are `-m` (RabbitMQ host), `-r` (RSTAR directory), `-i` and `-o`
(input and output paths), `-s` (service), `-e` (extra command-line arguments),
`-j` (JSON configuration), and `-p` (message priority). Use `-h` for the
complete option list. RSTAR jobs can take optional object IDs; when none are
provided, all objects in the R* directory are submitted.

## Derivative Generation ##

To add jobs to the task queue, run the 'add-mb-job.pl' script.  For example, to generate derivatives for the book 'cornell_aco000384' from the Cornell ACO collection, the invocation would look like:

```bash
add-mb-job -m localhost \
    -r /root/path/of/rstar/content/cornell/aco \
    -s  book_publisher:create_derivatives \
    cornell_aco000384
```

Here the '-r' option sets the path to the rstar directory, '-m' specifies the hostname of RabbitMQ message broker, and the 's' flag sets the service to "book_publisher:create_derivatives" which tells the workers to generate derivatives for the book.

To generate derivatives and a PDF for a book, simply change the -s to
`book_publisher:gen_all`:

```bash
add-mb-job -m localhost \
    -r /root/path/of/rstar/content/cornell/aco \
    -s book_publisher:gen_all \
    cornell_aco000384
```

If you would like to process all wip ids in the rstar directory, do no specify any wip ids on the command line.

```bash
add-mb-job -m localhost \
    -r /root/path/of/rstar/content/cornell/aco \
    -s book_publisher:gen_all
```

If you have a file containing a list of wip ids you could do the following:

```bash
cat wip_id_list.txt | xargs add-mb-job \
    -r /root/path/of/rstar/content/cornell/aco \
    -s book_publisher:gen_all
```

OR

```bash
add-mb-job \
    -r /root/path/of/rstar/content/cornell/aco \
    -s book_publisher:gen_all `cat wip_id_list.txt`
```

## Audio/Video Encoding ##

To transcode videos in a wip structure, you would use an invocation similar to above but would change the service to "video:transcode".  For example:

```bash
add-mb-job -m localhost \
    -r /root/path/of/rstar/provider/collection \
    -s  video:transcode \
    wip_id
```

To transcode videos from an input directory and place the newly encoded files in an output directory, set the -i and -o options for source and destination directories.

```bash
add-mb-job -m localhost \
    -i /input/directory \
    -o /output/directory \
    -s  video:transcode
```

To transcode a single video file, set -i to the path of the source video file, set -o to the output prefix.  If the -o option is not set, the output prefix will be determined by the path of the source video file.

```bash
add-mb-job -m localhost \
    -i /path/to/video/file \
    -o /output/path/prefix \
    -s  video:transcode
```

To encode audio files:

```bash
add-mb-job -m localhost \
    -i /input/directory \
    -o /output/directory \
    -s  audio:transcode
```

## Testing ##

The following service values allow you to test the system by running
simple command line utilities.

The values are

```bash
util:env
util:fortune
util:nope
util:ping
```

which execute the ping, fortune, and false commands respectively.
You will only need to set the -m and -s options for add-mb-job
to run these utilities.  For example,

```bash
add-mb-job -m 192.168.11.2 -s util:nope
```

We should expect the example above to result in a failed job since
we are running /bin/false which returns a non-zero exit value.

## Available Services ##

The `-s` option accepts the following services:

### Audio ###

- `audio:transcode` transcodes mezzanine audio files to AAC. It accepts an R*
    directory and optional object IDs, or an input file/directory and output
    path.
- `audio:transcribe` generates an English SRT caption file from one media
    input. Set `-i` to the media file and `-o` to the new SRT file.

### BagIt ###

- `bagit:validate` verifies a BagIt package at `-i`; set `-o` to the
    validation log path.

### Book Publishing ###

Except for `book_publisher:shrink_aco_pdf`, these services accept an RSTAR
directory and optional object IDs, or an input directory and output directory
using `-i` and `-o`. `shrink_aco_pdf` takes input and output PDF file paths.

- `book_publisher:create_derivatives` generates derivative images.
- `book_publisher:create_dmakers` generates derivative images in dmaker mode.
- `book_publisher:stitch_pages` stitches page images.
- `book_publisher:create_pdf` generates a PDF.
- `book_publisher:create_ocr` generates OCR data.
- `book_publisher:create_map` generates a KML map.
- `book_publisher:gen_all` generates derivative images and a PDF.
- `book_publisher:make_yaiglobal_upload_pdf` creates low-resolution upload
    derivatives and PDF, then cleans auxiliary files.
- `book_publisher:hocr2pdf` generates dmaker derivatives and creates a PDF
    from hOCR.
- `book_publisher:shrink_aco_pdf` shrinks an input PDF; set `-i` and `-o` to
    the input and output files.

### Utilities ###

- `util:env` reports worker Ruby, gem, and environment details.
- `util:fortune` runs the `fortune` command.
- `util:nope` intentionally fails by running `false`.
- `util:ping` checks connectivity by pinging `www.google.com`.

### Video ###

- `video:convert_iso` converts an input ISO file to an output path; set `-i`
    and `-o`.
- `video:transcode` transcodes video files. It accepts an R* directory and
    optional object IDs, or an input file/directory and output path. Directory
    transcoding also creates contact sheets for supported video files.

## Additional Options ##

Sending jobs to the task-queue causes the backends scripts to run with their default options.  For example, transcoding runs with the "Movie Scenes" encoding profile.  At present, there are two ways to change this behavior.  You can set the -e flag to pass in extra arguments or you create a text file containing a json hash which sets the key "extra_args".  Let's say we want to change the encoding profile to "HIDVL"

Method 1:

```bash
add-mb-job -m localhost \
    -i /input/directory \
    -o /output/directory \
    -s  video:transcode \
    -e "--profiles_path profiles-hidvl.xml"
```

Method 2:

```bash
   echo '{"extra_args": "--profiles_path profiles-hidvl.xml"}' > config.json
add-mb-job -m localhost \
    -i /input/directory \
    -o /output/directory \
    -s  video:transcode \
    -j config.json
```

## JSON Configuration ##

In the above example, you saw how we set extra_args using a json file to change the default profile for video encoding.  You can use it to also set different parameters for the backend class.  You can find more examples in the doc/samples directory.

## Job Status ##

You will notice that once a job is submitted, you will receive a batch number which you can use to track all jobs within a batch.  This is probably more useful when submitting rstar related jobs because you might have multiple wip ids in a batch.

Once you've added jobs to the queue, you'll probably want to check their status.  This can be accomplished by running the following script:

```bash
check-job-status
```

This will produce a simple table that shows the wip id, job status (such as 'processing', 'success', 'error'), and date of completion.

To check the status of jobs in a particular batch, please add the batch number to the -b switch.  For example to check the status of batch 3:

```bash
check-job-status -b 3
```

You can see the list of available options by specifying the '--help' flag.
