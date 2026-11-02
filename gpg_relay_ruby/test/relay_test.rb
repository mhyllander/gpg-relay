# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'logger'
require_relative '../relay'

class RelayTest < Minitest::Test
  def setup
    @relay = Relay.new({}, Logger.new(File::NULL))
  end

  def test_dial_assuan_rejects_malformed_descriptors
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'socket')
      ['no newline', "abc\n#{'x' * 16}", "99999\n#{'x' * 16}", "6910\nshort"].each do |content|
        File.binwrite(path, content)
        assert_nil @relay.dial_assuan(path), content.inspect
      end
    end
  end

  def test_dial_assuan_sends_nonce
    server = TCPServer.new('127.0.0.1', 0)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'socket')
      File.binwrite(path, "#{server.addr[1]}\n#{'n' * 16}")
      client = @relay.dial_assuan(path)
      assert_equal 'n' * 16, server.accept.read(16)
      client.close
    end
  ensure
    server&.close
  end

  def test_command_output_runs_without_a_shell
    assert_equal "a b'c $HOME", Relay.command_output('echo', "a b'c $HOME")
    assert_raises(RuntimeError) { Relay.command_output('false') }
  end
end
