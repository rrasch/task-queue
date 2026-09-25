# frozen_string_literal: true

require 'json'
require_relative './audio'
require_relative './bagit'
require_relative './book_publisher'
require_relative './exceptions'
require_relative './helpers'
require_relative './tqcommon'
require_relative './util'
require_relative './video'

ALLOWED_STATES = %w[processing success error].freeze

# Task
class Task # rubocop:disable Metrics/ClassLength
  def initialize(body:, logger:, # rubocop:disable Metrics/ParameterLists
                 channel:, exchange:, delivery_tag:, services: nil)
    @data = {}
    @body = body
    @logger = logger
    @ch = channel
    @x = exchange
    @delivery_tag = delivery_tag
    @services = services || TQCommon.services.map { |svc| [svc, true] }.to_h
    @class_name = nil
    @result = nil
  end

  def [](key)
    @data[key]
  end

  def []=(key, value)
    @data[key] = value
  end

  def process
    parse_body
    validate_service
    validate_class
    validate_paths
    mark_processing
    exec
    validate_result
    mark_done
  end

  def format
    JSON.pretty_generate(@data)
  end

  private

  def parse_body
    req = JSON.parse(@body)
    @data.merge!(req)
    @logger.info "Parsed and merged JSON: #{format}"
  rescue JSON::JSONError => e
    raise InvalidTaskError, "Can't parse JSON '#{@body}' - #{e.message}"
  end

  def validate_service
    svc = "#{@data['class']}:#{@data['operation']}"
    raise InvalidTaskError, "Invalid service: #{svc}" unless @services.key?(svc)
  end

  def validate_class
    @class_name = classify(@data['class'].to_s.strip)

    raise InvalidTaskError, "Class name isn't defined." if @class_name.empty?

    return if class_exists?(@class_name)

    raise InvalidTaskError, "Class '#{@class_name}' doesn't exist."
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  # rubocop:disable Metrics/MethodLength
  def validate_paths
    return if @data['class'] == 'util'

    has_rstar = @data.key?('rstar_dir')
    has_input = @data.key?('input_path')
    has_output = @data.key?('output_path')

    unless has_rstar || (has_input && has_output)
      raise InvalidTaskError,
            'Must provide rstar_dir OR input_path+output_path'
    end

    if has_rstar && (has_input || has_output)
      raise InvalidTaskError,
            'rstar_dir cannot be used with input_path/output_path'
    end

    if has_input != has_output # rubocop:disable Style/GuardClause
      raise InvalidTaskError,
            'input_path and output_path must be provided together'
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  # rubocop:enable Metrics/MethodLength

  def validate_result
    unless @result.is_a?(Hash) &&
           @result.key?(:success) &&
           @result.key?(:output) &&
           [true, false].include?(@result[:success])
      raise InvalidTaskError, "Invalid result: #{@result}"
    end
  end

  def exec
    @logger.debug "Creating new '#{@class_name}' object"
    obj = Object.const_get(@class_name).new(@data, @logger)
    method_name = @data['operation'].to_s.tr('-', '_')

    unless obj.respond_to?(method_name)
      raise InvalidTaskError,
            "Method '#{@class_name}.#{method_name}' does not exist."
    end

    @logger.debug "Executing '#{method_name}'"
    @result = obj.send(method_name)
  end

  def publish
    unless ALLOWED_STATES.include?(@data['state'])
      raise "Invalid state: #{@data['state']}"
    end

    routing_key = "task_queue.#{@data['state']}"
    msg = format
    @logger.debug "Publishing to #{routing_key} #{msg}"
    @x.publish(msg, routing_key: routing_key)
  end

  def mark_processing
    @data['state']       = 'processing'
    @data['worker_host'] = ip_addr
    @data['started']     = now
    publish
  end

  def mark_done
    state = @result[:success] ? 'success' : 'error'
    @logger.debug "[x] Done #{state.capitalize}! result=#{@result}"

    @data['state']     = state
    @data['output']    = @result[:output]
    @data['completed'] = now
    publish

    @logger.debug 'Sending acknowledgment'
    @ch.ack(@delivery_tag)
    @logger.info "Task completed #{format}"
  end

  public

  def mark_error(exc, err_msg)
    @logger.error "#{exc.class}: #{err_msg}"
    if @data.any?
      @data['state'] = 'error'
      @data['output'] = err_msg
      @data['completed'] = now
      publish
    end
    @logger.debug("Rejecting message: #{@delivery_tag}")
    @ch.nack(@delivery_tag, false, false)
  end
end
