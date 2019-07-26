# Copyright 2019 The NATS Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'nats/io/client'
require 'spec_helper'

describe 'Client - Cluster TLS reconnect' do

  before(:all) do
    s1_config_opts = {
      'pid_file'      => '/tmp/nats_cluster_s1.pid',
      'host'          => '127.0.0.1',
      'port'          => 4232,
      'cluster_port'  => 6232
    }

    s2_config_opts = {
      'pid_file'      => '/tmp/nats_cluster_s2.pid',
      'host'          => '127.0.0.1',
      'port'          => 4233,
      'cluster_port'  => 6233
    }

    s3_config_opts = {
      'pid_file'      => '/tmp/nats_cluster_s3.pid',
      'host'          => '127.0.0.1',
      'port'          => 4234,
      'cluster_port'  => 6234
    }

    nodes = []
    configs = [s1_config_opts, s2_config_opts, s3_config_opts]
    configs.each do |config_opts|
      nodes << NatsServerControl.init_with_config_from_string(%Q(
        http: 'localhost:#{config_opts['port'] + 4000}'
        host: '#{config_opts['host']}'
        port:  #{config_opts['port']}
        pid_file: '#{config_opts['pid_file']}'

        debug: true
        trace: true

        log_file: '/tmp/nats_rb_#{config_opts['port']}.log'

        tls {
          cert_file:  "./spec/configs/certs/server.pem"
          key_file:   "./spec/configs/certs/key.pem"
          ca_file:   "./spec/configs/certs/ca.pem"
          # verify:    true
          timeout:   10
        }

        ping_interval = 2

        authorization {
          user: hello
          password: world
          timeout: 5
        }

        cluster {
          host: '#{config_opts['host']}'
          port: #{config_opts['cluster_port']}

          authorization {
            user: hello
            password: world
            timeout: 5
          }

          routes = [
            'nats://hello:world@127.0.0.1:#{s1_config_opts['cluster_port']}'
          ]
        }
      ), config_opts)
    end

    @s1, @s2, @s3 = nodes
  end

  context 'with auto discovery using seed node' do
    before(:each) do
      # Only start initial seed node
      @s1.start_server(true)
    end

    after(:each) do
      @s1.kill_server
    end

    it 'should reconnect to nodes discovered from seed server' do
      # Nodes join to cluster before we try to connect
      [@s2, @s3].each do |s|
        s.start_server(true)
      end

      begin
        initial_connected_server = nil
        last_connected_server = nil
        reconnects = 0
        servers_after_connect = 0
        with_em_timeout(30) do
          NATS.on_error do |e|
            puts "ERROR: #{e}"
          end

          NATS.on_close do |e|
            puts "Connection closed"
          end

          NATS.on_disconnect do |e|
            puts "Disconnected! Reason: #{e}"
            puts "Pending data: #{NATS.pending_data_size}"
          end

          NATS.on_reconnect do |nats|
            puts "Reconnected! Pending data: #{nats.pending_data_size}"
            reconnects += 1
            server_pool_state = nats.server_pool
          end

          nc = NATS::IO::Client.new

          seed_server = "tls://hello:world@127.0.0.1:4232"

          # Connect to first server only and trigger reconnect
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.set_params
          ctx.ca_file = "./spec/configs/certs/ca.pem"
          ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
          ctx.verify_hostname = false
          nc.connect(seed_server, tls: { context: ctx })

          # Thread.new do
          #   loop do
          #     payload = 'A' * 16384
          #     nc.publish("foo", payload)
          #     sleep 0.01
          #   end
          # end

          NATS.start(seed_server,
                       dont_randomize_servers: true,
                       tls: {
                         private_key_file:'./spec/configs/certs/key.pem',
                         cert_chain_file: './spec/configs/certs/server.pem',
                         ca_file:         './spec/configs/certs/ca.pem',
                         verify_peer: false
                       }) do |nats|
            initial_connected_server = nats.connected_server
            expect(nats.server_pool.first[:uri]).to eql(nats.connected_server)

            nats.subscribe("foo") do |msg|
              p "Recv: #{msg[0..10]}"
              sleep 10
            end

            Thread.new do
              payload = 'EM' + ('B' * 16384)
              EM.add_periodic_timer(0.001) do
                nats.publish("foo", payload)
              end
            end

            EM.add_timer(2) do
              # Should have detected new server asynchronously
              servers_after_connect = nats.server_pool.count
              expect(nats.server_pool.first[:uri]).to eql(nats.connected_server)

              # First reconnect
              @s1.kill_server
              
              # Restart the seed server
              EM.add_timer(3) do
                @s1.start_server(true)
              end
            end
          end
        end
      ensure
        # Wrap up test
        [@s1, @s2, @s3].each do |s|
          s.kill_server
        end
      end
    end
  end
end
