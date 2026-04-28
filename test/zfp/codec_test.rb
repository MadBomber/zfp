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

  # --- lossy modes ---

  def test_fixed_rate_compress_decompress
    codec  = Zfp::Codec.new(type: :double, shape: [64], mode: :fixed_rate, rate: 4.0)
    data   = Array.new(64) { rand }
    result = codec.decompress(codec.compress(data))
    assert_equal 64, result.length
  end

  def test_fixed_accuracy_within_tolerance
    tolerance = 0.01
    codec     = Zfp::Codec.new(type: :double, shape: [100], mode: :fixed_accuracy, tolerance: tolerance)
    data      = Array.new(100) { rand * 100 }
    result    = codec.decompress(codec.compress(data))
    data.each_with_index do |orig, i|
      assert_operator (orig - result[i]).abs, :<=, tolerance * 10
    end
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
