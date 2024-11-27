#!/bin/bash

# Update consumer timeout to 3 days
rabbitmqctl eval 'application:set_env(rabbit, consumer_timeout, 259200000).'

rabbitmqctl eval 'application:get_env(rabbit, consumer_timeout).'
