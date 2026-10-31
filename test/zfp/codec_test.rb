# frozen_string_literal: true

require "test_helper"

class CodecTest < Minitest::Test
  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
  end

  # --- validation ---

  def test_raises_invalid_type_for_unknown_type
    assert_raises(Zfp::InvalidType) { Zfp::Codec.new(type: :float128, shape: [10], mode: :reversible) }
  end

  def test_raises_invalid_mode_for_unknown_mode
    assert_raises(Zfp::InvalidMode) { Zfp::Codec.new(type: :double, shape: [10], mode: :bogus) }
  end

  def test_raises_invalid_shape_for_empty_shape
    assert_raises(Zfp::InvalidShape) { Zfp::Codec.new(type: :double, shape: [], mode: :reversible) }
  end

  def test_raises_invalid_shape_for_5d
    assert_raises(Zfp::InvalidShape) { Zfp::Codec.new(type: :double, shape: [1] * 5, mode: :reversible) }
  end

  def test_raises_invalid_params_fixed_rate_missing_rate
    assert_raises(Zfp::InvalidParams) { Zfp::Codec.new(type: :double, shape: [10], mode: :fixed_rate) }
  end

  def test_raises_invalid_params_fixed_precision_missing_precision
    assert_raises(Zfp::InvalidParams) { Zfp::Codec.new(type: :double, shape: [10], mode: :fixed_precision) }
  end

  def test_raises_invalid_params_fixed_accuracy_missing_tolerance
    assert_raises(Zfp::InvalidParams) { Zfp::Codec.new(type: :double, shape: [10], mode: :fixed_accuracy) }
  end

  # --- integer types are reversible-only ---

  %i[int32 int64].each do |type|
    { fixed_rate: { rate: 8.0 }, fixed_precision: { precision: 16 }, fixed_accuracy: { tolerance: 1.0 } }.each do |mode, params|
      define_method("test_#{type}_rejects_#{mode}") do
        err = assert_raises(Zfp::InvalidMode) { Zfp::Codec.new(type: type, shape: [16], mode: mode, **params) }
        assert_match(/reversible/, err.message)
      end
    end
  end

  # --- shape must match the data length (would otherwise read past the buffer) ---

  def test_compress_raises_when_data_shorter_than_shape
    codec = Zfp::Codec.new(type: :double, shape: [100], mode: :reversible)
    err = assert_raises(Zfp::InvalidShape) { codec.compress((1..10).map(&:to_f)) }
    assert_match(/100 elements but data has 10/, err.message)
  end

  def test_compress_raises_when_data_longer_than_shape
    codec = Zfp::Codec.new(type: :double, shape: [10], mode: :reversible)
    assert_raises(Zfp::InvalidShape) { codec.compress((1..100).map(&:to_f)) }
  end

  def test_compress_raises_for_empty_data
    codec = Zfp::Codec.new(type: :double, shape: [4], mode: :reversible)
    assert_raises(Zfp::InvalidShape) { codec.compress([]) }
  end

  def test_compress_raises_when_numo_shape_disagrees_with_codec_shape
    codec = Zfp::Codec.new(type: :double, shape: [4, 4], mode: :reversible)
    assert_raises(Zfp::InvalidShape) { codec.compress(Numo::DFloat.new(3, 4).seq) }
  end

  def test_compress_accepts_nested_ruby_array_matching_shape
    codec = Zfp::Codec.new(type: :double, shape: [2, 2], mode: :reversible)
    bytes = codec.compress([[1.0, 2.0], [3.0, 4.0]])
    assert_equal [1.0, 2.0, 3.0, 4.0], codec.decompress(bytes)
  end

  # --- reversible mode: 4 types × 4 shapes ---

  %i[float double int32 int64].each do |type|
    [[16], [4, 4], [2, 2, 4], [2, 2, 2, 2]].each do |shape|
      define_method("test_reversible_#{type}_#{shape.join('x')}_compresses") do
        data  = %i[float double].include?(type) ? (1..16).map { |i| i * 1.5 } : (1..16).to_a
        codec = Zfp::Codec.new(type: type, shape: shape, mode: :reversible)
        assert_kind_of String, codec.compress(data)
      end

      define_method("test_reversible_#{type}_#{shape.join('x')}_roundtrips_exactly") do
        data   = %i[float double].include?(type) ? (1..16).map { |i| i * 1.5 } : (1..16).to_a
        codec  = Zfp::Codec.new(type: type, shape: shape, mode: :reversible)
        result = codec.decompress(codec.compress(data))
        assert_equal data.length, result.length
        data.each_with_index { |v, i| assert_equal v, result[i] }
      end
    end
  end

  def test_reversible_roundtrips_nan_and_infinities
    data  = [1.0, Float::NAN, Float::INFINITY, -Float::INFINITY, 0.0, -0.0] + [2.0] * 10
    codec = Zfp::Codec.new(type: :double, shape: [16], mode: :reversible)
    back  = codec.decompress(codec.compress(data))
    assert back[1].nan?
    assert_equal data[2..], back[2..]
  end

  def test_reversible_roundtrips_int32_and_int64_extremes
    codec32 = Zfp::Codec.new(type: :int32, shape: [4], mode: :reversible)
    d32 = [-2**31, 2**31 - 1, 0, -1]
    assert_equal d32, codec32.decompress(codec32.compress(d32))
    codec64 = Zfp::Codec.new(type: :int64, shape: [4], mode: :reversible)
    d64 = [-2**63, 2**63 - 1, 0, -1]
    assert_equal d64, codec64.decompress(codec64.compress(d64))
  end

  # --- lossy modes ---

  def test_fixed_rate_compress_decompress
    codec  = Zfp::Codec.new(type: :double, shape: [64], mode: :fixed_rate, rate: 4.0)
    data   = Array.new(64) { rand }
    result = codec.decompress(codec.compress(data))
    assert_equal 64, result.length
  end

  def test_fixed_rate_output_size_is_rate_times_count
    codec = Zfp::Codec.new(type: :double, shape: [256], mode: :fixed_rate, rate: 8.0)
    assert_equal 256, codec.compress(Array.new(256) { rand }).bytesize
  end

  def test_fixed_accuracy_within_tolerance
    tolerance = 0.01
    codec     = Zfp::Codec.new(type: :double, shape: [1000], mode: :fixed_accuracy, tolerance: tolerance)
    data      = Array.new(1000) { rand * 1000 }
    result    = codec.decompress(codec.compress(data))
    max_err   = data.zip(result).map { |a, b| (a - b).abs }.max
    assert_operator max_err, :<=, tolerance
  end

  def test_fixed_precision_round_trip_length
    codec  = Zfp::Codec.new(type: :double, shape: [50], mode: :fixed_precision, precision: 16)
    data   = Array.new(50) { rand * 1000 }
    result = codec.decompress(codec.compress(data))
    assert_equal 50, result.length
  end

  # --- Numo::NArray ---

  def test_numo_dfloat_roundtrip
    codec  = Zfp::Codec.new(type: :double, shape: [8], mode: :reversible, numo: true)
    na     = Numo::DFloat[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    result = codec.decompress(codec.compress(na))
    assert_kind_of Numo::DFloat, result
    assert_equal na.to_a, result.to_a
  end

  def test_numo_2d_roundtrip_preserves_row_major_layout
    codec  = Zfp::Codec.new(type: :double, shape: [3, 5], mode: :reversible, numo: true)
    na     = Numo::DFloat.new(3, 5).seq
    result = codec.decompress(codec.compress(na))
    assert_equal [3, 5], result.shape
    assert_equal na.to_a, result.to_a
  end

  # --- pack / unpack ---

  def test_pack_unpack_roundtrip
    codec = Zfp::Codec.new(type: :double, shape: [10], mode: :reversible)
    data  = (1..10).map(&:to_f)
    packed = codec.pack(data)
    type, shape, mode, params, _numo, compressed = Zfp::Packer.decode(packed)
    result = Zfp::Codec.new(type: type, shape: shape, mode: mode, **params).decompress(compressed)
    assert_equal data, result
  end
end
