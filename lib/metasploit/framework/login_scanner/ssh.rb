require 'net/ssh'
require 'metasploit/framework/login_scanner/base'

module Metasploit
  module Framework
    module LoginScanner

      # This is the LoginScanner class for dealing with the Secure Shell protocol.
      # It is responsible for taking a single target, and a list of credentials
      # and attempting them. It then saves the results.
      #
      class SSH
        include Metasploit::Framework::LoginScanner::Base

        #
        # CONSTANTS
        #

        CAN_GET_SESSION      = true
        DEFAULT_PORT         = 22
        LIKELY_PORTS         = [ DEFAULT_PORT ]
        LIKELY_SERVICE_NAMES = [ 'ssh' ]
        PRIVATE_TYPES        = [ :password, :ssh_key ]
        REALM_KEY            = nil

        VERBOSITIES = [
            :debug,
            :info,
            :warn,
            :error,
            :fatal
        ]
        # @!attribute ssh_socket
        #   @return [Net::SSH::Connection::Session] The current SSH connection
        attr_accessor :ssh_socket
        # @!attribute verbosity
        #   The verbosity level for the SSH client.
        #
        #   @return [Symbol] An element of {VERBOSITIES}.
        attr_accessor :verbosity

        validates :verbosity,
          presence: true,
          inclusion: { in: VERBOSITIES }

        # (see {Base#attempt_login})
        # @note The caller *must* close {#ssh_socket}
        def attempt_login(credential)
          self.ssh_socket = nil
          opt_hash = {
            :port          => port,
            :disable_agent => true,
            :config        => false,
            :verbose       => verbosity,
            :proxies       => proxies
          }
          case credential.private_type
          when :password, nil
            opt_hash.update(
              :auth_methods  => ['password','keyboard-interactive'],
              :password      => credential.private,
            )
          when :ssh_key
            opt_hash.update(
              :auth_methods  => ['publickey'],
              :key_data      => credential.private,
            )
          end

          result_options = {
            credential: credential
          }
          begin
            ::Timeout.timeout(connection_timeout) do
              self.ssh_socket = Net::SSH.start(
                host,
                credential.public,
                opt_hash
              )
            end
          rescue ::EOFError, Net::SSH::Disconnect, Rex::AddressInUse, Rex::ConnectionError, ::Timeout::Error
            result_options.merge!( proof: nil, status: Metasploit::Model::Login::Status::UNABLE_TO_CONNECT)
          rescue Net::SSH::Exception
            result_options.merge!( proof: nil, status: Metasploit::Model::Login::Status::INCORRECT)
          end

          unless result_options.has_key? :status
            if ssh_socket
              proof = gather_proof
              result_options.merge!( proof: proof, status: Metasploit::Model::Login::Status::SUCCESSFUL)
            else
              result_options.merge!( proof: nil, status: Metasploit::Model::Login::Status::INCORRECT)
            end
          end

          ::Metasploit::Framework::LoginScanner::Result.new(result_options)
        end

        private

        # This method attempts to gather proof that we successfuly logged in.
        # @return [String] The proof of a connection, May be empty.
        def gather_proof
          proof = ''
          begin
            Timeout.timeout(5) do
              proof = ssh_socket.exec!("id\n").to_s
              if(proof =~ /id=/)
                proof << ssh_socket.exec!("uname -a\n").to_s
              else
                # Cisco IOS
                if proof =~ /Unknown command or computer name/
                  proof = ssh_socket.exec!("ver\n").to_s
                else
                  proof << ssh_socket.exec!("help\n?\n\n\n").to_s
                end
              end
            end
          rescue ::Exception
          end
          proof
        end

        def set_sane_defaults
          self.connection_timeout = 30 if self.connection_timeout.nil?
          self.port = DEFAULT_PORT if self.port.nil?
          self.verbosity = :fatal if self.verbosity.nil?
        end

      end

    end
  end
end
