require 'minitest/autorun'
require_relative '../go_duration'

class GoDurationTest < Minitest::Test
  def test_go_duration_syntax
    {
      '0' => 0, '+0' => 0, '-0' => 0, '0s' => 0,
      '5m' => 300, '300s' => 300, '1m30s' => 90,
      '+1.5h' => 5400, '-1s' => -1, '-1m30s' => -90,
      '150ms' => Rational(15, 100), '.5s' => Rational(1, 2),
      '1.s' => 1, '1ns' => Rational(1, 1_000_000_000),
      '1us' => Rational(1, 1_000_000), '1µs' => Rational(1, 1_000_000),
      '1μs' => Rational(1, 1_000_000), '0.9ns' => 0,
      '0.5ns0.5ns' => 0,
      '.333333333333333333333h' => 1200,
      '9223372036854775807ns' => Rational(2**63 - 1, 1_000_000_000),
      '-9223372036854775808ns' => Rational(-2**63, 1_000_000_000),
    }.each do |input, expected|
      assert_equal expected, GoDuration.parse(input), input
    end
  end

  def test_invalid_durations
    ['', '5', '00', '1d', '1e3s', '1 s', ' 1s', '1s ', '.s',
     '1s-2s', '--1s', 'NaN', 'Infinity', '9223372036854775808ns',
     '-9223372036854775809ns', '2562048h', '9223372036854775807ns1ns'].each do |input|
      assert_raises(ArgumentError, input) { GoDuration.parse(input) }
    end
  end
end
