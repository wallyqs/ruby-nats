require 'spec_helper'
require 'yaml'

describe 'Client - cluster' do

  before(:all) do

    auth_options = {
      'user'     => 'derek',
      'password' => 'bella',
      'token'    => 'deadbeef',
      'timeout'  => 5
    }

    s1_config_opts = {
      'pid_file'      => '/tmp/nats_cluster_s1.pid',
      'authorization' => auth_options,
      'host'          => '127.0.0.1',
      'port'          => 4242,
      'cluster_port'  => 6222
    }

    s2_config_opts = {
      'pid_file'      => '/tmp/nats_cluster_s2.pid',
      'authorization' => auth_options,
      'host'          => '127.0.0.1',
      'port'          => 4243,
      'cluster_port'  => 6223
    }

    nodes = []
    configs = [s1_config_opts, s2_config_opts]
    configs.each do |config_opts|

      other_nodes_configs = configs.select do |conf|
        conf['cluster_port'] != config_opts['cluster_port']
      end

      routes = []
      other_nodes_configs.each do |conf|
        routes <<  "nats-route://foo:bar@127.0.0.1:#{conf['cluster_port']}"
      end

      nodes << NatsServerControl.init_with_config_from_string(%Q(
        host: '#{config_opts['host']}'
        port:  #{config_opts['port']}

        pid_file: '#{config_opts['pid_file']}'

        authorization {
          user: '#{auth_options["user"]}'
          password: '#{auth_options["password"]}'
          timeout: #{auth_options["timeout"]}
        }

        cluster {
          host: '#{config_opts['host']}'
          port: #{config_opts['cluster_port']}

          authorization {
            user: foo
            password: bar
            timeout: #{auth_options["timeout"]}
          }

          routes = [
            #{routes.join("\n            ")}
          ]
        }
      ), config_opts)
    end

    @s1, @s2 = nodes
  end

  before(:each) do
    [@s1, @s2].each do |s|
      s.start_server(true)
    end
  end

  after(:each) do
    [@s1, @s2].each do |s|
      s.kill_server
    end
  end

  it 'should properly connect to different servers' do
    EM.run do
      c1 = NATS.connect(:uri => @s1.uri)
      c2 = NATS.connect(:uri => @s2.uri)
      wait_on_connections([c1, c2]) do
        EM.stop
      end
    end
  end

  it 'should properly route plain messages between different servers' do
    data = 'Hello World!'
    received = 0
    EM.run do
      c1 = NATS.connect(:uri => @s1.uri)
      c2 = NATS.connect(:uri => @s2.uri)
      c1.subscribe('foo') do |msg|
        expect(msg).to eql(data)
        received += 1
      end
      c2.subscribe('foo') do |msg|
        expect(msg).to eql(data)
        received += 1
      end
      wait_on_routes_connected([c1, c2]) do
        c2.publish('foo', data)
        c2.publish('foo', data)
        flush_routes([c1, c2]) { EM.stop }
      end
    end
    expect(received).to eql(4)
  end

  it 'should properly route messages for distributed queues on different servers' do
    data = 'Hello World!'
    to_send = 100
    received = c1_received = c2_received = 0
    EM.run do
      c1 = NATS.connect(:uri => @s1.uri)
      c2 = NATS.connect(:uri => @s2.uri)
      c1.subscribe('foo', :queue => 'bar') do |msg|
        expect(msg).to eql(data)
        c1_received += 1
        received += 1
      end
      c2.subscribe('foo', :queue => 'bar') do |msg|
        expect(msg).to eql(data)
        c2_received += 1
        received += 1
      end

      wait_on_routes_connected([c1, c2]) do
        (1..to_send).each { c2.publish('foo', data) }
        flush_routes([c1, c2]) { EM.stop }
      end
    end

    expect(received).to eql(to_send)
    expect(c1_received < to_send).to eql(true)
    expect(c2_received < to_send).to eql(true)
    expect(c1_received).to be_within(25).of(to_send/2)
    expect(c2_received).to be_within(25).of(to_send/2)
  end

  it 'should properly route messages for distributed queues and normal subscribers on different servers' do
    data = 'Hello World!'
    to_send = 100
    received = c1_received = c2_received = 0
    EM.run do
      c1 = NATS.connect(:uri => @s1.uri)
      c2 = NATS.connect(:uri => @s2.uri)
      c1.subscribe('foo') do |msg|
        expect(msg).to eql(data)
        received += 1
      end
      c1.subscribe('foo', :queue => 'bar') do |msg|
        expect(msg).to eql(data)
        c1_received += 1
        received += 1
      end
      c2.subscribe('foo', :queue => 'bar') do |msg|
        expect(msg).to eql(data)
        c2_received += 1
        received += 1
      end

      wait_on_routes_connected([c1, c2]) do
        (1..to_send).each { c2.publish('foo', data) }
        flush_routes([c1, c2]) { EM.stop }
      end
    end

    expect(received).to eql(to_send*2) # queue subscriber + normal subscriber
    expect(c1_received < to_send).to eql(true) 
    expect(c2_received < to_send).to eql(true)
    expect(c1_received).to be_within(15).of(to_send/2)
    expect(c2_received).to be_within(15).of(to_send/2)
  end

  it 'should properly route messages for distributed queues with multiple groups on different servers' do
    data = 'Hello World!'
    to_send = 100
    received = c1a_received = c2a_received = 0
    c1b_received = c2b_received = 0

    EM.run do
      c1 = NATS.connect(:uri => @s1.uri)
      c2 = NATS.connect(:uri => @s2.uri)

      c1.subscribe('foo') do |msg|
        expect(msg).to eql(data)
        received += 1
      end
      c1.subscribe('foo', :queue => 'bar') do |msg|
        expect(msg).to eql(data)
        c1a_received += 1
        received += 1
      end
      c1.subscribe('foo', :queue => 'baz') do |msg|
        expect(msg).to eql(data)
        c1b_received += 1
        received += 1
      end

      c2.subscribe('foo', :queue => 'bar') do |msg|
        expect(msg).to eql(data)
        c2a_received += 1
        received += 1
      end

      c2.subscribe('foo', :queue => 'baz') do |msg|
        expect(msg).to eql(data)
        c2b_received += 1
        received += 1
      end

      wait_on_routes_connected([c1, c2]) do
        (1..to_send).each { c2.publish('foo', data) }
        (1..to_send).each { c1.publish('foo', data) }
        flush_routes([c1, c2]) { EM.stop }
      end
    end

    expect(received).to eql(to_send*6) # 2 queue subscribers + normal subscriber * 2 pub loops
    expect(c1a_received).to be_within(25).of(to_send)
    expect(c2a_received).to be_within(25).of(to_send)
    expect(c1b_received).to be_within(25).of(to_send)
    expect(c2b_received).to be_within(25).of(to_send)
  end

  it 'should properly route messages for distributed queues with reply subjects on different servers' do
    data = 'Hello World!'
    to_send = 100
    received = c1_received = c2_received = 0
    EM.run do
      c1 = NATS.connect(:uri => @s1.uri)
      c2 = NATS.connect(:uri => @s2.uri)

      c1.subscribe('foo', :queue => 'reply_test') do |msg|
        expect(msg).to eql(data)
        c1_received += 1
        received += 1
      end
      c2.subscribe('foo', :queue => 'reply_test') do |msg|
        expect(msg).to eql(data)
        c2_received += 1
        received += 1
      end
      wait_on_routes_connected([c1, c2]) do
        (1..to_send).each { c2.publish('foo', data, 'bar') }
        flush_routes([c1, c2]) { EM.stop }
      end
    end

    expect(received).to eql(to_send)
    expect(c1_received < to_send).to eql(true)
    expect(c2_received < to_send).to eql(true)
    expect(c1_received).to be_within(25).of(to_send/2)
    expect(c2_received).to be_within(25).of(to_send/2)
  end
end
