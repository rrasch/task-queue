# frozen_string_literal: true

require 'json'
require 'socket'

def classify(str)
  str.split(/[_-]/).collect(&:capitalize).join
end

def class_exists?(class_name)
  klass = Module.const_get(class_name)
  klass.is_a?(Class)
rescue NameError
  false
end

def ip_addr
  Socket.ip_address_list.detect do |ip|
    ip.ipv4? and !ip.ipv4_loopback? and !ip.ipv4_multicast?
  end.ip_address
end

def now
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

def beautify(data)
  JSON.pretty_generate(data.reject { |key, _| key.to_s == 'logger' })
end
