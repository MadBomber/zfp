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

  def test_decompress_with_numo_true_returns_numo
    bytes  = Zfp.compress(@data, type: :double, shape: @shape, mode: :reversible)
    result = Zfp.decompress(bytes, type: :double, shape: @shape, mode: :reversible, numo: true)
    assert_kind_of Numo::DFloat, result
  end

  def test_compress_infers_type_and_shape_from_numo
    na    = Numo::DFloat.cast(@data)
    bytes = Zfp.compress(na, mode: :reversible)
    assert_kind_of String, bytes
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

  def test_unpack_raises_packer_error_on_garbage
    assert_raises(Zfp::PackerError) { Zfp.unpack("not a valid packed buffer") }
  end
end
