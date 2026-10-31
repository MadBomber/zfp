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

  def with_output_field(shape = [16], type = :double)
    out_buf   = ::FFI::MemoryPointer.new(:uint8, shape.reduce(:*) * Zfp::TypeCoercion::ELEMENT_SIZE[type])
    out_field = Zfp::Field.new(type, shape, out_buf)
    yield out_field, out_buf
  ensure
    out_field&.free
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
    with_output_field do |out_field, out_buf|
      stream.decompress(out_field, compressed)
      assert_equal @data, Zfp::TypeCoercion.from_buffer(out_buf, :double, [16], false)
    end
  end

  def test_fixed_rate_compresses_without_error
    Zfp::Stream.new(:fixed_rate, { rate: 4.0 }).compress(@field)
  end

  # --- decompression input safety ---

  def test_decompress_empty_input_raises
    with_output_field do |out_field, _|
      assert_raises(Zfp::DecompressionFailed) { Zfp::Stream.new(:reversible, {}).decompress(out_field, "") }
    end
  end

  def test_decompress_truncated_reversible_input_does_not_crash
    # Variable-rate streams cannot be size-checked, but the zero-padded input
    # buffer must keep libzfp from reading past the end.
    stream     = Zfp::Stream.new(:reversible, {})
    compressed = stream.compress(@field)
    with_output_field do |out_field, _|
      stream.decompress(out_field, compressed[0, 1])
    end
  end

  def test_decompress_garbage_input_does_not_crash
    with_output_field([1000]) do |out_field, _|
      Zfp::Stream.new(:reversible, {}).decompress(out_field, "x" * 8)
    end
  end

  def test_decompress_truncated_fixed_rate_input_raises
    stream     = Zfp::Stream.new(:fixed_rate, { rate: 8.0 })
    compressed = stream.compress(@field)
    with_output_field do |out_field, _|
      err = assert_raises(Zfp::DecompressionFailed) { stream.decompress(out_field, compressed[0..-2]) }
      assert_match(/truncated/, err.message)
    end
  end

  def test_decompress_exact_fixed_rate_input_succeeds
    stream     = Zfp::Stream.new(:fixed_rate, { rate: 8.0 })
    compressed = stream.compress(@field)
    with_output_field { |out_field, _| stream.decompress(out_field, compressed) }
  end

  # --- fixed_rate_size matches what libzfp writes ---

  def test_fixed_rate_size_matches_compressed_size_for_many_shapes
    [[256], [16, 16], [4, 8, 8], [4, 4, 4, 4], [7], [5, 3], [3, 3, 3], [1]].each do |shape|
      [1.0, 3.3, 8.0, 16.0].each do |rate|
        n      = shape.reduce(:*)
        buf    = Zfp::TypeCoercion.to_buffer(Array.new(n) { rand }, :double)
        field  = Zfp::Field.new(:double, shape, buf)
        stream = Zfp::Stream.new(:fixed_rate, { rate: rate })
        bytes  = stream.compress(field)
        assert_equal bytes.bytesize, stream.fixed_rate_size(field), "shape=#{shape} rate=#{rate}"
        field.free
      end
    end
  end

  def test_actual_rate_reflects_libzfp_minimum
    stream = Zfp::Stream.new(:fixed_rate, { rate: 0.5 })
    stream.compress(@field)
    assert_operator stream.actual_rate, :>, 0.5
  end
end
