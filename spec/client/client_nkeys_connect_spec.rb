require 'spec_helper'

describe 'Client - NATS v2 Auth' do

  context 'with NKEYS and JWT' do
    before(:each) do
      config_opts = {
        'pid_file'      => '/tmp/nats_nkeys_jwt.pid',
        'host'          => '127.0.0.1',
        'port'          => 4722,
      }
      @s = NatsServerControl.init_with_config_from_string(%Q(
        authorization { 
          timeout: 2
        }

        port = #{config_opts['port']}
        operator = "./spec/configs/nkeys/op.jwt"

        # This is for account resolution.
        resolver = MEMORY

         # This is a map that can preload keys:jwts into a memory resolver.
         resolver_preload = {
           # foo
           AD7SEANS6BCBF6FHIB7SQ3UGJVPW53BXOALP75YXJBBXQL7EAFB6NJNA : "eyJ0eXAiOiJqd3QiLCJhbGciOiJlZDI1NTE5In0.eyJqdGkiOiIyUDNHU1BFSk9DNlVZNE5aM05DNzVQVFJIV1pVRFhPV1pLR0NLUDVPNjJYSlZESVEzQ0ZRIiwiaWF0IjoxNTUzODQwNjE1LCJpc3MiOiJPRFdJSUU3SjdOT1M3M1dWQk5WWTdIQ1dYVTRXWFdEQlNDVjRWSUtNNVk0TFhUT1Q1U1FQT0xXTCIsIm5hbWUiOiJmb28iLCJzdWIiOiJBRDdTRUFOUzZCQ0JGNkZISUI3U1EzVUdKVlBXNTNCWE9BTFA3NVlYSkJCWFFMN0VBRkI2TkpOQSIsInR5cGUiOiJhY2NvdW50IiwibmF0cyI6eyJsaW1pdHMiOnsic3VicyI6LTEsImNvbm4iOi0xLCJpbXBvcnRzIjotMSwiZXhwb3J0cyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwid2lsZGNhcmRzIjp0cnVlfX19.COiKg5EFK4Gb2gA7vtKHQK7vjMEUx-RMWYuN-Bg-uVOFs9GLwW7Dxc4TcN-poBGBEkwKnleiA9SjYO3y4-AqBQ"

           # bar
           AAXPTP32BD73YW3ACUY6DPXKWBSUW4VEZNE3LD4FUOFDP6KDU43PQVU2 : "eyJ0eXAiOiJqd3QiLCJhbGciOiJlZDI1NTE5In0.eyJqdGkiOiJPQ1dUQkRQTzVETjRSV0lFNEtJQ1BQWkszUEhHV0dQUVFKNFVET1pQSTVaRzJQUzZKVkpBIiwiaWF0IjoxNTUzODQwNjE5LCJpc3MiOiJPRFdJSUU3SjdOT1M3M1dWQk5WWTdIQ1dYVTRXWFdEQlNDVjRWSUtNNVk0TFhUT1Q1U1FQT0xXTCIsIm5hbWUiOiJiYXIiLCJzdWIiOiJBQVhQVFAzMkJENzNZVzNBQ1VZNkRQWEtXQlNVVzRWRVpORTNMRDRGVU9GRFA2S0RVNDNQUVZVMiIsInR5cGUiOiJhY2NvdW50IiwibmF0cyI6eyJsaW1pdHMiOnsic3VicyI6LTEsImNvbm4iOi0xLCJpbXBvcnRzIjotMSwiZXhwb3J0cyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwid2lsZGNhcmRzIjp0cnVlfX19.KY2fBvYyNCA0dYS7I6_rETGHT4YGkWZSh03XhXxwAvJ8XCfKlVJRY82U-0ERg01SFtPTZ-6BYu-sty1E67ioDA"
         }
      ), config_opts)
      @s.start_server(true)
    end

    after(:each) do
      @s.kill_server
    end

    it 'should connect to server and publish messages' do
      with_em_timeout do |f|
        NATS.start(servers: ["nats://127.0.0.1:4722"], user_credentials: "./spec/configs/nkeys/foo-user.creds") do
          NATS.subscribe("hello") do |msg|
            f.resume
          end
          NATS.publish('hello', 'world')
        end
      end
    end

    it 'should fail with auth error if no user credentials present' do
      expect do 
        NATS.start(servers: ["nats://127.0.0.1:4722"]) do
          NATS.publish('hello', 'world') do
            EM.stop
          end
        end
      end.to raise_error(NATS::AuthError)
    end
  end

  context 'with NKEYS only' do
    before(:each) do
      config_opts = {
        'pid_file'      => '/tmp/nats_nkeys.pid',
        'host'          => '127.0.0.1',
        'port'          => 4723,
      }
      @s = NatsServerControl.init_with_config_from_string(%Q(
        authorization { 
          timeout: 2
        }

        port = #{config_opts['port']}
        
        accounts {
          acme {
            users [
              {
                 nkey = "UCK5N7N66OBOINFXAYC2ACJQYFSOD4VYNU6APEJTAVFZB2SVHLKGEW7L",
                 permissions = {
                   subscribe = {
                     allow = ["hello", "_INBOX.>"]
                     deny = ["foo"]
                   }
                   publish = {
                     allow = ["hello", "_INBOX.>"]
                     deny = ["foo"]
                   }
                 }
              }
            ]
          }
        }
      ), config_opts)
      @s.start_server(true)
    end

    after(:each) do
      @s.kill_server
    end

    it 'should connect to the server and publish messages' do
      with_em_timeout do |f|
        NATS.start(servers: ["nats://127.0.0.1:4723"], nkeys_seed: "./spec/configs/nkeys/foo-user.nk") do
          NATS.subscribe("hello") do |msg|
            f.resume
          end
          NATS.publish('hello', 'world')
        end
      end
    end
  end

  context 'with NKEYS and JWT' do
    before(:each) do
      config_opts = {
        'pid_file'      => '/tmp/nats_nkeys_jwt.pid',
        'host'          => '127.0.0.1',
        'port'          => 4722,
      }
      @s = NatsServerControl.init_with_config_from_string(%Q(
        authorization { 
          timeout: 2
        }

        port = #{config_opts['port']}
        operator = "./spec/configs/nkeys/op.jwt"

        # This is for account resolution.
        resolver = MEMORY

         # This is a map that can preload keys:jwts into a memory resolver.
         resolver_preload = {
           # foo
           AD7SEANS6BCBF6FHIB7SQ3UGJVPW53BXOALP75YXJBBXQL7EAFB6NJNA : "eyJ0eXAiOiJqd3QiLCJhbGciOiJlZDI1NTE5In0.eyJqdGkiOiIyUDNHU1BFSk9DNlVZNE5aM05DNzVQVFJIV1pVRFhPV1pLR0NLUDVPNjJYSlZESVEzQ0ZRIiwiaWF0IjoxNTUzODQwNjE1LCJpc3MiOiJPRFdJSUU3SjdOT1M3M1dWQk5WWTdIQ1dYVTRXWFdEQlNDVjRWSUtNNVk0TFhUT1Q1U1FQT0xXTCIsIm5hbWUiOiJmb28iLCJzdWIiOiJBRDdTRUFOUzZCQ0JGNkZISUI3U1EzVUdKVlBXNTNCWE9BTFA3NVlYSkJCWFFMN0VBRkI2TkpOQSIsInR5cGUiOiJhY2NvdW50IiwibmF0cyI6eyJsaW1pdHMiOnsic3VicyI6LTEsImNvbm4iOi0xLCJpbXBvcnRzIjotMSwiZXhwb3J0cyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwid2lsZGNhcmRzIjp0cnVlfX19.COiKg5EFK4Gb2gA7vtKHQK7vjMEUx-RMWYuN-Bg-uVOFs9GLwW7Dxc4TcN-poBGBEkwKnleiA9SjYO3y4-AqBQ"

           # bar
           AAXPTP32BD73YW3ACUY6DPXKWBSUW4VEZNE3LD4FUOFDP6KDU43PQVU2 : "eyJ0eXAiOiJqd3QiLCJhbGciOiJlZDI1NTE5In0.eyJqdGkiOiJPQ1dUQkRQTzVETjRSV0lFNEtJQ1BQWkszUEhHV0dQUVFKNFVET1pQSTVaRzJQUzZKVkpBIiwiaWF0IjoxNTUzODQwNjE5LCJpc3MiOiJPRFdJSUU3SjdOT1M3M1dWQk5WWTdIQ1dYVTRXWFdEQlNDVjRWSUtNNVk0TFhUT1Q1U1FQT0xXTCIsIm5hbWUiOiJiYXIiLCJzdWIiOiJBQVhQVFAzMkJENzNZVzNBQ1VZNkRQWEtXQlNVVzRWRVpORTNMRDRGVU9GRFA2S0RVNDNQUVZVMiIsInR5cGUiOiJhY2NvdW50IiwibmF0cyI6eyJsaW1pdHMiOnsic3VicyI6LTEsImNvbm4iOi0xLCJpbXBvcnRzIjotMSwiZXhwb3J0cyI6LTEsImRhdGEiOi0xLCJwYXlsb2FkIjotMSwid2lsZGNhcmRzIjp0cnVlfX19.KY2fBvYyNCA0dYS7I6_rETGHT4YGkWZSh03XhXxwAvJ8XCfKlVJRY82U-0ERg01SFtPTZ-6BYu-sty1E67ioDA"
         }
      ), config_opts)
      @s.start_server(true)
    end

    after(:each) do
      @s.kill_server
    end

    it 'should connect to server and publish messages' do
      with_em_timeout do |f|
        NATS.start(servers: ["nats://127.0.0.1:4722"], user_credentials: "./spec/configs/nkeys/foo-user.creds") do
          NATS.subscribe("hello") do |msg|
            f.resume
          end
          NATS.publish('hello', 'world')
        end
      end
    end

    it 'should fail with auth error if no user credentials present' do
      expect do 
        NATS.start(servers: ["nats://127.0.0.1:4722"]) do
          NATS.publish('hello', 'world') do
            EM.stop
          end
        end
      end.to raise_error(NATS::AuthError)
    end
  end

  context 'with NKEYS and TLS enabled' do
    before(:each) do

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
          host: '#{config_opts['host']}'
          port:  #{config_opts['port']}
          pid_file: '#{config_opts['pid_file']}'

          tls {
            cert_file:  "./spec/configs/certs/nats-service.localhost/server.pem"
            key_file:   "./spec/configs/certs/nats-service.localhost/server-key.pem"
            ca_file:   "./spec/configs/certs/nats-service.localhost/ca.pem"
            timeout:   10
          }

          accounts {
            acme {
              users [
                {
                   nkey = "UCK5N7N66OBOINFXAYC2ACJQYFSOD4VYNU6APEJTAVFZB2SVHLKGEW7L",
                   permissions = {
                     subscribe = {
                       allow = ["hello", "_INBOX.>"]
                       deny = ["foo"]
                     }
                     publish = {
                       allow = ["hello", "_INBOX.>"]
                       deny = ["foo"]
                     }
                   }
                }
              ]
            }
          }

          cluster {
            host: '#{config_opts['host']}'
            port: #{config_opts['cluster_port']}

            authorization {
              user: foo
              password: bar
              timeout: 5
            }

            routes = [
              'nats://hello:world@127.0.0.1:#{s1_config_opts['cluster_port']}'
            ]
          }
        ), config_opts)
      end

      @s1, @s2, @s3 = nodes

      config_opts = {
        'pid_file'      => '/tmp/nats_nkeys.pid',
        'host'          => '127.0.0.1',
        'port'          => 4723,
      }
      @s = NatsServerControl.init_with_config_from_string(%Q(
        authorization { 
          timeout: 2
        }

        port = #{config_opts['port']}
        
        accounts {
          acme {
            users [
              {
                 nkey = "UCK5N7N66OBOINFXAYC2ACJQYFSOD4VYNU6APEJTAVFZB2SVHLKGEW7L",
                 permissions = {
                   subscribe = {
                     allow = ["hello", "_INBOX.>"]
                     deny = ["foo"]
                   }
                   publish = {
                     allow = ["hello", "_INBOX.>"]
                     deny = ["foo"]
                   }
                 }
              }
            ]
          }
        }
      ), config_opts)
      @s.start_server(true)
    end

    after(:each) do
      @s.kill_server
    end

    it 'should connect to the server and publish messages' do
      with_em_timeout do |f|
        NATS.start(servers: ["nats://127.0.0.1:4723"], nkeys_seed: "./spec/configs/nkeys/foo-user.nk") do
          NATS.subscribe("hello") do |msg|
            f.resume
          end
          NATS.publish('hello', 'world')
        end
      end
    end
  end
end
