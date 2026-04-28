# frozen_string_literal: true

require "test_helper"

class StreamTest < Minitest::Test
  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
    @data   = (1..16).map(&:to_f)
    @buffer = Zfp::TypeCoercion.to_buffer(@data, :double)
    @field  = Zfp::Field.new(:double, [16], @buffer)
  end

  def teardown
    @field&.free
  end

  def test_reversible_compresses_without_error
    Zfp::Stream.new(:reversible, {}).compress(@field)
  end

  def test_reversible_compress_returns_nonempty_bytes
    bytes = Zfp::Stream.new(:reversible, {}).compress(@field)
    assert_kind_of String, bytes
    assert_operator bytes.bytesize, :>, 0
  end

  def test_reversible_round_trip
    stream     = Zfp::Stream.new(:reversible, {})
    compressed = stream.compress(@field)

    out_buf   = ::FFI::MemoryPointer.new(:uint8, @data.length * 8)
    out_field = Zfp::Field.new(:double, [16], out_buf)
    stream.decompress(out_field, compressed)
    result = Zfp::TypeCoercion.from_buffer(out_buf, :double, [16], false)
    out_field.free

    assert_equal @data, result
  end

  def test_fixed_rate_compresses_without_error
    Zfp::Stream.new(:fixed_rate, { rate: 4.0 }).compress(@field)
  end
end
