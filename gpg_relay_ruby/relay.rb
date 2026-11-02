require 'open3'
require 'socket'

class Relay
  def initialize(options, logger)
    @options = options
    @logger = logger
  end

  # Runs a command without a shell and returns its chomped stdout.
  def self.command_output(*command)
    output, status = Open3.capture2(*command)
    raise "#{command.join(' ')} failed with #{status}" unless status.success?

    output.chomp
  end

  # Returns a connected socket, or nil (after logging) when the descriptor is unusable.
  def dial_assuan(socket_path)
    # the assuan "socket" file contains a port number (ascii characters), followed by a new line character (10), then a
    # nonce (16 bytes)
    port_text, separator, nonce = File.binread(socket_path).partition("\n")
    port = Integer(port_text, 10, exception: false)
    if separator.empty? || port.nil? || !port.between?(1, 65_535)
      @logger.error {"#{socket_path} is not a valid assuan socket descriptor"}
      return nil
    end
    @logger.debug {"assuan socket #{socket_path} -> TCP 127.0.0.1:#{port}"}
    if nonce.bytesize != 16
      @logger.error {"#{socket_path} nonce length is #{nonce.bytesize} != 16"}
      return nil
    end
    gpg_agent = TCPSocket.new '127.0.0.1', port
    gpg_agent.write nonce # send the nonce to "authenticate"
    gpg_agent
  end

  def relay(client, server)
    Thread.new do
      directions = [
        Thread.new {copy_direction(client, server)},
        Thread.new {copy_direction(server, client)},
      ]
      directions.each(&:join)
    ensure
      @logger.debug 'closing sockets'
      close_socket(client)
      close_socket(server)
    end
  end

  private

  def copy_direction(source, destination)
    copied = IO.copy_stream(source, destination)
    @logger.debug {"copied #{copied} bytes before EOF"}
    destination.shutdown(Socket::SHUT_WR)
  rescue IOError, SystemCallError => e
    @logger.error "socket relay failed: #{e.inspect}"
    close_socket(source)
    close_socket(destination)
  end

  def close_socket(socket)
    socket.close unless socket.closed?
  rescue IOError, SystemCallError => e
    @logger.debug {"socket close failed: #{e.inspect}"}
  end
end
