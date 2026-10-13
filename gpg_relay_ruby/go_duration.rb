# frozen_string_literal: true

# Parse the duration syntax used by Go's time.ParseDuration, returning seconds.
module GoDuration
  UNITS = {
    'ns' => 1, 'us' => 1_000, 'µs' => 1_000, 'μs' => 1_000,
    'ms' => 1_000_000, 's' => 1_000_000_000,
    'm' => 60_000_000_000, 'h' => 3_600_000_000_000,
  }.freeze

  def self.parse(value)
    remaining = value.sub(/\A[+-]/, '')
    negative = value.start_with?('-')
    return 0 if remaining == '0'

    invalid = "invalid duration: #{value.inspect}"
    raise ArgumentError, invalid if remaining.empty?

    nanoseconds = 0
    until remaining.empty?
      match = /\A([0-9]+(?:\.[0-9]*)?|\.[0-9]+)(ns|us|µs|μs|ms|s|m|h)/.match(remaining)
      raise ArgumentError, invalid unless match

      integer, fraction = match[1].split('.', 2)
      unit = UNITS.fetch(match[2])
      nanoseconds += integer.to_i * unit
      if fraction && !fraction.empty?
        # Match Go's floating-point scaling and bounded fractional precision.
        digits = 0
        scale = 1.0
        fraction.each_byte do |digit|
          next_digits = digits * 10 + digit - 48
          break if digits > (2**63 - 1) / 10 || next_digits > 2**63

          digits = next_digits
          scale *= 10
        end
        nanoseconds += (digits.to_f * (unit.to_f / scale)).to_i if digits > 0
      end
      limit = negative ? 2**63 : 2**63 - 1
      raise ArgumentError, invalid if nanoseconds > limit

      remaining = match.post_match
    end
    nanoseconds = -nanoseconds if negative
    Rational(nanoseconds, 1_000_000_000)
  end
end
