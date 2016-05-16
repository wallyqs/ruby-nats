require 'spec_helper'

describe 'Client - TLS spec' do

  context 'when server does not support TLS' do

    before(:all) do
      @non_tls_server = NatsServerControl.new("nats://localhost:4222")
      @non_tls_server.start_server
    end

    after(:all) do
      @non_tls_server.kill_server unless @non_tls_server.was_running?
    end

    it 'should error if client requires TLS' do
      errors = []
      closed_cb_called = false
      reconnect_cb_called = false
      disconnect_cb_called = false

      # Default callbacks to be used
      NATS.on_error {|e| errors << e; EM.stop }
      NATS.on_close {|e| closed_cb_called = true }
      NATS.on_reconnect {|e| reconnect_cb_called = true }
      NATS.on_disconnect {|e| disconnect_cb_called = true }

      options = {
        :uri => 'nats://localhost:4222',
        :reconnect => false,
        :tls => {
          :ssl_version => :TLSv1_2,
          :protocols => [:tlsv1_2],
          :private_key_file => './spec/configs/certs/key.pem',
          :cert_chain_file  => './spec/configs/certs/server.pem',
          :verify_peer      => false
        }
      }

      NATS.start(options) { NATS.stop }
      expect(errors.count).to eql(2)
      expect(errors[0]).to be_a(NATS::ClientError)
      expect(errors[0].to_s).to eql("TLS/SSL not supported by server")
      expect(errors[1]).to be_a(NATS::ConnectError)
      expect(closed_cb_called).to eq(true)
      expect(reconnect_cb_called).to eq(false)

      # Technically we were never connected to the NATS service
      # in that server so we don' call disconnect right now.
      expect(disconnect_cb_called).to eq(false)
    end
  end

  context 'when server requires TLS and no auth needed' do

    before(:all) do
      @tls_no_auth = NatsServerControl.new("nats://localhost:4444", '/tmp/test-nats-4444.pid', "-c ./spec/configs/tls-no-auth.conf")
      @tls_no_auth.start_server
    end

    after(:all) do
      @tls_no_auth.kill_server unless @tls_no_auth.was_running?
    end

    it 'should error if client does not set secure connection, callbacks set' do
      errors = []
      closed_cb_called = false
      reconnect_cb_called = false
      disconnect_cb_called = false

      # Default callbacks to be used
      NATS.on_close {|e| closed_cb_called = true }
      NATS.on_reconnect {|e| reconnect_cb_called = true }
      NATS.on_disconnect {|e| disconnect_cb_called = true }
      
      EM.run do
        NATS.on_error {|e| errors << e; EM.stop }
        NATS.connect(:uri => 'nats://localhost:4444', :reconnect => false)
      end
      expect(errors.count).to eql(1)
      expect(errors[0]).to be_a(NATS::ConnectError)
      expect(closed_cb_called).to eq(true)
      expect(reconnect_cb_called).to eq(false)
      expect(disconnect_cb_called).to eq(false)
    end
  end

  context 'when server requires TLS and authentication' do

    before(:all) do
      @tls_auth = NatsServerControl.new("nats://localhost:4443", '/tmp/test-nats-4443.pid', "-c ./spec/configs/tls.conf")
      @tls_auth.start_server
    end

    after(:all) do
      @tls_auth.kill_server unless @tls_auth.was_running?
    end

    it 'should error if client does not set secure connection, callbacks set' do
      errors = []
      EM.run do
        NATS.on_error {|e| errors << e; EM.stop }
        NATS.connect(:uri => 'nats://localhost:4443', :reconnect => false)
      end
      expect(errors.count).to eql(1)

      # Client disconnected from server
      expect(errors[0]).to be_a(NATS::ConnectError)
    end

    it 'should error if client does not set secure connection and stop trying to reconnect eventually' do
      errors = []
      EM.run do
        NATS.on_error do |e|
          errors << e
          EM.stop
        end
        NATS.connect(:uri => 'nats://localhost:4443')
      end
      expect(errors.count).to eql(1)

      # Client disconnected from server
      expect(errors[0]).to be_a(NATS::ConnectError)
    end

    it 'should reject secure connection when using deprecated versions' do
      errors = []
      connected_cb_called = false
      disconnect_cb_called = false
      closed_cb_called = false
      EM.run do
        NATS.on_error do |e|
          p e
          errors << e
          EM.stop
        end
        NATS.on_disconnect do |e|
          disconnect_cb_called = true
          EM.stop
        end

        NATS.on_close do
          closed_cb_called = true
          EM.stop
        end
        
        nc = NATS.connect({ :servers => ['nats://secret:deadbeef@127.0.0.1:4443'],
                            :tls => { :ssl_version => :sslv2 }}) do
          connected_cb_called = true
        end
        nc.subscribe("hello")
        nc.flush do
          nc.close
        end
      end
      expect(errors.count).to eql(1)
      expect(errors[0]).to be_a(NATS::ConnectError)
      expect(connected_cb_called).to be(false)
      expect(closed_cb_called).to be(true)
      expect(disconnect_cb_called).to be(false)
    end

    it 'should connect securely to server and authorize' do
      errors = []
      connected_cb_called = false
      disconnect_cb_called = false
      closed_cb_called = false
      EM.run do
        NATS.on_error do |e|
          errors << e
        end

        NATS.on_disconnect do |e|
          disconnect_cb_called = true
          EM.stop
        end

        NATS.on_close do
          closed_cb_called = true
          EM.stop
        end

        options = {
          :servers => ['nats://secret:deadbeef@127.0.0.1:4443'],
          :max_reconnect_attempts => 1,
          :dont_randomize_servers => true,
          :tls => {
            # :ssl_version => :TLSv1_2,
            # :protocols => [:tlsv1_2],
            # :private_key_file => './spec/configs/certs/key.pem',
            # :cert_chain_file  => './spec/configs/certs/server.pem',
            # :verify_peer      => false
          }
        }

        nc = NATS.connect(options) do
          connected_cb_called = true
        end

        messages = []

        nc.subscribe("hello") do |msg|
          messages << msg
        end
        nc.flush do
          nc.publish("hello", "world") do
            nc.unsubscribe("hello")
            nc.close
            expect(messages.count).to eql(1)
          end
        end
      end
      expect(errors.count).to eql(0)
      expect(closed_cb_called).to be(true)
      expect(disconnect_cb_called).to be(false)
    end

    it 'should connect securely with default TLS and protocols options' do
      errors = []
      connected_cb_called = false
      disconnect_cb_called = false
      closed_cb_called = false
      EM.run do
        NATS.on_error do |e|
          errors << e
        end

        NATS.on_disconnect do |e|
          disconnect_cb_called = true
          EM.stop
        end

        NATS.on_close do
          closed_cb_called = true
          EM.stop
        end

        options = {
          :servers => ['nats://secret:deadbeef@127.0.0.1:4443'],
          :max_reconnect_attempts => 1,
          :dont_randomize_servers => true,
          :tls => {
            # :ssl_version => :TLSv1_2,
            # :protocols => [:tlsv1_2],
            # :private_key_file => './spec/configs/certs/key.pem',
            # :cert_chain_file  => './spec/configs/certs/server.pem',
            # :verify_peer      => false
          }
        }

        nc = NATS.connect(options) do
          connected_cb_called = true
        end

        messages = []

        nc.subscribe("hello") do |msg|
          messages << msg
        end
        nc.flush do
          nc.publish("hello", "world") do
            nc.unsubscribe("hello")
            nc.close
            expect(messages.count).to eql(1)
          end
        end
      end
      expect(errors.count).to eql(0)
      expect(closed_cb_called).to be(true)
      expect(disconnect_cb_called).to be(false)
    end    
  end

  context 'when server requires TLS, certificates and authentication' do

    before(:all) do
      @tls_verify_auth = NatsServerControl.new("nats://localhost:4445", '/tmp/test-nats-4445.pid', "-c ./spec/configs/tlsverify.conf")
      @tls_verify_auth.start_server
    end

    after(:all) do
      @tls_verify_auth.kill_server unless @tls_verify_auth.was_running?
    end

    it 'should error if client does not set secure connection, callbacks set' do
      errors = []
      EM.run do
        NATS.on_error {|e| errors << e; EM.stop }
        NATS.connect(:uri => 'nats://localhost:4445', :reconnect => false)
      end
      expect(errors.count).to eql(1)

      # Client disconnected from server
      expect(errors[0]).to be_a(NATS::ConnectError)
    end

    it 'should error if client does not set secure connection and stop trying to reconnect eventually' do
      errors = []
      EM.run do
        NATS.on_error do |e|
          errors << e
          EM.stop
        end
        NATS.connect(:uri => 'nats://localhost:4445')
      end
      expect(errors.count).to eql(1)

      # Client disconnected from server
      expect(errors[0]).to be_a(NATS::ConnectError)
    end

    it 'should reject secure connection if no certificate is provided' do
      errors = []
      connected_cb_called = false
      disconnect_cb_called = false
      closed_cb_called = false
      EM.run do
        NATS.on_error do |e|
          errors << e
          EM.stop
        end
        NATS.on_disconnect do |e|
          disconnect_cb_called = true
          EM.stop
        end

        NATS.on_close do
          closed_cb_called = true
          EM.stop
        end
        
        nc = NATS.connect({ :servers => ['nats://secret:deadbeef@127.0.0.1:4445'],
                            :tls => { :ssl_version => :TLSv1_2 }}) do
          connected_cb_called = true
        end
        nc.subscribe("hello")
        nc.flush do
          nc.close
        end
      end
      expect(errors.count).to eql(1)
      expect(errors[0]).to be_a(NATS::ConnectError)
      expect(connected_cb_called).to eq(false)      
      expect(closed_cb_called).to eq(true)
      expect(disconnect_cb_called).to eq(false)
    end

    it 'should connect securely to server and authorize' do
      errors = []
      connected_cb_called = false
      disconnect_cb_called = false
      closed_cb_called = false
      EM.run do
        NATS.on_error do |e|
          errors << e
        end

        NATS.on_disconnect do |e|
          disconnect_cb_called = true
          EM.stop
        end

        NATS.on_close do
          closed_cb_called = true
          EM.stop
        end

        options = {
          :servers => ['nats://secret:deadbeef@127.0.0.1:4445'],
          :max_reconnect_attempts => 1,
          :dont_randomize_servers => true,
          :tls => {
            :ssl_version => :TLSv1_2,
            :protocols => [:tlsv1_2],
            :private_key_file => './spec/configs/certs/key.pem',
            :cert_chain_file  => './spec/configs/certs/server.pem',
            :verify_peer      => false
          }
        }

        nc = NATS.connect(options) do
          connected_cb_called = true
        end

        messages = []

        nc.subscribe("hello") do |msg|
          messages << msg
        end
        nc.flush do
          nc.publish("hello", "world") do
            nc.unsubscribe("hello")
            nc.close
            expect(messages.count).to eql(1)
          end
        end
      end
      expect(errors.count).to eql(0)
      expect(closed_cb_called).to be(true)
      expect(disconnect_cb_called).to be(false)
    end

    it 'should connect securely with default TLS and protocols options' do
      errors = []
      connected_cb_called = false
      disconnect_cb_called = false
      closed_cb_called = false
      EM.run do
        NATS.on_error do |e|
          errors << e
        end

        NATS.on_disconnect do |e|
          disconnect_cb_called = true
          EM.stop
        end

        NATS.on_close do
          closed_cb_called = true
          EM.stop
        end

        options = {
          :servers => ['nats://secret:deadbeef@127.0.0.1:4445'],
          :max_reconnect_attempts => 1,
          :dont_randomize_servers => true,
          :tls => {
            :private_key_file => './spec/configs/certs/key.pem',
            :cert_chain_file  => './spec/configs/certs/server.pem',
          }
        }

        nc = NATS.connect(options) do
          connected_cb_called = true
        end

        messages = []

        nc.subscribe("hello") do |msg|
          messages << msg
        end
        nc.flush do
          nc.publish("hello", "world") do
            nc.unsubscribe("hello")
            nc.close
            expect(messages.count).to eql(1)
          end
        end
      end
      expect(errors.count).to eql(0)
      expect(closed_cb_called).to be(true)
      expect(disconnect_cb_called).to be(false)
    end    
  end  

  # it 'should reject without' proper cert if required by server'
  # it 'should be authorized with proper cert'
end
