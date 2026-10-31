# frozen_string_literal: true

require "test_helper"

class ZfpTest < Minitest::Test
  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
    @data  = (1..20).map(&:to_f)
    @shape = [20]
  end

  def test_version_is_defined
    refute_nil Zfp::VERSION
  end

  def test_compress_returns_nonempty_string
    bytes = Zfp.compress(@data, type: :double, shape: @shape, mode: :reversible)
    assert_kind_of String, bytes
    assert_operator bytes.bytesize, :>, 0
  end

  def test_compress_decompress_roundtrip
    bytes  = Zfp.compress(@data, type: :double, shape: @shape, mode: :reversible)
    result = Zfp.decompress(bytes, type: :double, shape: @shape, mode: :reversible)
    assert_equal @data, result
  end

  def test_compress_requires_type_for_ruby_array
    assert_raises(Zfp::InvalidType) { Zfp.compress(@data, shape: @shape, mode: :reversible) }
  end

  def test_compress_requires_shape_for_ruby_array
    assert_raises(Zfp::InvalidShape) { Zfp.compress(@data, type: :double, mode: :reversible) }
  end

  def test_compress_raises_when_shape_does_not_match_data
    assert_raises(Zfp::InvalidShape) { Zfp.compress(@data, type: :double, shape: [100], mode: :reversible) }
  end

  def test_decompress_with_numo_true_returns_numo
    bytes  = Zfp.compress(@data, type: :double, shape: @shape, mode: :reversible)
    result = Zfp.decompress(bytes, type: :double, shape: @shape, mode: :reversible, numo: true)
    assert_kind_of Numo::DFloat, result
  end

  def test_decompress_empty_bytes_raises
    assert_raises(Zfp::DecompressionFailed) { Zfp.decompress("", type: :double, shape: @shape, mode: :reversible) }
  end

  def test_compress_infers_type_and_shape_from_numo
    na    = Numo::DFloat.cast(@data)
    bytes = Zfp.compress(na, mode: :reversible)
    assert_kind_of String, bytes
  end

  def test_2d_numo_roundtrip_through_module_methods
    na     = Numo::DFloat.new(6, 7).seq
    bytes  = Zfp.compress(na, mode: :reversible)
    result = Zfp.decompress(bytes, type: :double, shape: [6, 7], mode: :reversible, numo: true)
    assert_equal na.to_a, result.to_a
  end

  def test_pack_unpack_roundtrip_ruby_array
    packed = Zfp.pack(@data, type: :double, shape: @shape, mode: :reversible)
    result = Zfp.unpack(packed)
    assert_equal @data, result
  end

  def test_pack_unpack_roundtrip_numo_returns_numo
    na     = Numo::DFloat.cast(@data)
    packed = Zfp.pack(na, mode: :reversible)
    result = Zfp.unpack(packed)
    assert_kind_of Numo::DFloat, result
    assert_equal @data, result.to_a
  end

  def test_pack_unpack_2d_numo_preserves_shape
    na     = Numo::DFloat.new(5, 8).seq
    result = Zfp.unpack(Zfp.pack(na, mode: :reversible))
    assert_equal [5, 8], result.shape
    assert_equal na.to_a, result.to_a
  end

  def test_pack_with_explicit_numo_true_on_ruby_array_unpacks_to_numo
    packed = Zfp.pack(@data, type: :double, shape: @shape, mode: :reversible, numo: true)
    assert_kind_of Numo::DFloat, Zfp.unpack(packed)
  end

  def test_pack_with_explicit_numo_false_on_numo_array_unpacks_to_array
    packed = Zfp.pack(Numo::DFloat.cast(@data), mode: :reversible, numo: false)
    assert_kind_of Array, Zfp.unpack(packed)
  end

  def test_pack_uses_v2_header
    packed = Zfp.pack(@data, type: :double, shape: @shape, mode: :reversible)
    assert_kind_of Zfp::Packed, packed
    assert_equal "ZFP\x02".b, packed.to_str[0, 4].b
  end

  def test_unpack_raises_packer_error_on_garbage
    assert_raises(Zfp::PackerError) { Zfp.unpack("not a valid packed buffer") }
  end

  def test_unpack_lossy_reads_params_from_header
    data   = Array.new(256) { |i| Math.sin(i * 0.1) * 100 }
    packed = Zfp.pack(data, type: :double, shape: [256], mode: :fixed_accuracy, tolerance: 0.01)
    back   = Zfp.unpack(packed)
    assert_operator data.zip(back).map { |a, b| (a - b).abs }.max, :<=, 0.01
  end
end
