# frozen_string_literal: true

require "test_helper"

class PackerTest < Minitest::Test
  RAW_BYTES = "compressed_data_stub"

  ROUND_TRIP_CASES = [
    { type: :float,  shape: [100],        mode: :reversible,      params: {},                  numo: false },
    { type: :double, shape: [10, 20],     mode: :fixed_rate,      params: { rate: 4.0 },       numo: false },
    { type: :int32,  shape: [5, 5, 5],    mode: :fixed_precision, params: { precision: 16 },   numo: false },
    { type: :int64,  shape: [2, 2, 2, 2], mode: :fixed_accuracy,  params: { tolerance: 0.001 }, numo: true  }
  ].freeze

  ROUND_TRIP_CASES.each do |c|
    define_method("test_roundtrip_#{c[:type]}_#{c[:mode]}_#{c[:shape].join('x')}") do
      packed = Zfp::Packer.encode(RAW_BYTES, **c)
      type, shape, mode, _params, numo, data = Zfp::Packer.decode(packed)
      assert_equal c[:type],  type
      assert_equal c[:shape], shape
      assert_equal c[:mode],  mode
      assert_equal c[:numo],  numo
      assert_equal RAW_BYTES, data
    end
  end

  def test_header_is_32_bytes_with_v2_magic
    packed = Zfp::Packer.encode(RAW_BYTES, type: :double, shape: [10], mode: :reversible)
    assert_equal 32 + RAW_BYTES.bytesize, packed.bytesize
    assert_equal "ZFP\x02".b, packed[0, 4].b
  end

  def test_encodes_rate_param
    packed = Zfp::Packer.encode(RAW_BYTES, type: :double, shape: [10], mode: :fixed_rate,
                                 params: { rate: 8.0 }, numo: false)
    _, _, _, params, = Zfp::Packer.decode(packed)
    assert_in_delta 8.0, params[:rate], 0.001
  end

  def test_encodes_precision_param
    packed = Zfp::Packer.encode(RAW_BYTES, type: :double, shape: [10], mode: :fixed_precision,
                                 params: { precision: 20 }, numo: false)
    _, _, _, params, = Zfp::Packer.decode(packed)
    assert_equal 20, params[:precision]
  end

  def test_encodes_tolerance_param
    packed = Zfp::Packer.encode(RAW_BYTES, type: :double, shape: [10], mode: :fixed_accuracy,
                                 params: { tolerance: 1e-5 }, numo: false)
    _, _, _, params, = Zfp::Packer.decode(packed)
    assert_in_delta 1e-5, params[:tolerance], 1e-10
  end

  def test_decode_accepts_any_to_str_object
    packed = Zfp::Packer.encode(RAW_BYTES, type: :double, shape: [10], mode: :reversible)
    wrapper = Zfp::Packed.new(packed)
    _, shape, = Zfp::Packer.decode(wrapper)
    assert_equal [10], shape
  end

  def test_decode_header_returns_metadata_without_payload
    packed = Zfp::Packer.encode(RAW_BYTES, type: :int64, shape: [2, 3], mode: :fixed_rate,
                                 params: { rate: 6.0 }, numo: true)
    h = Zfp::Packer.decode_header(packed)
    assert_equal({ type: :int64, shape: [2, 3], mode: :fixed_rate, params: { rate: 6.0 }, numo: true }, h)
  end

  def test_raises_packer_error_for_wrong_magic
    bad = "BAAD" + ("\x00" * 28) + RAW_BYTES
    err = assert_raises(Zfp::PackerError) { Zfp::Packer.decode(bad) }
    assert_match(/magic/, err.message)
  end

  def test_raises_packer_error_for_truncated_header
    err = assert_raises(Zfp::PackerError) { Zfp::Packer.decode("ZFP\x02\x00") }
    assert_match(/truncated/, err.message)
  end

  def test_raises_packer_error_for_unknown_type_byte
    bad = Zfp::Packer.encode(RAW_BYTES, type: :double, shape: [10], mode: :reversible)
    bad.setbyte(4, 9)
    assert_raises(Zfp::PackerError) { Zfp::Packer.decode(bad) }
  end

  # --- legacy v1 headers (gem 0.1.0) ---

  def legacy_v1(shape)
    packed = Zfp::Packer.encode(RAW_BYTES, type: :double, shape: shape, mode: :reversible)
    packed.setbyte(3, 1)   # ZFP\x02 -> ZFP\x01
    packed
  end

  def test_legacy_v1_1d_header_still_decodes
    _, shape, mode, _, _, data = Zfp::Packer.decode(legacy_v1([100]))
    assert_equal [100], shape
    assert_equal :reversible, mode
    assert_equal RAW_BYTES, data
  end

  def test_legacy_v1_multidimensional_header_is_rejected_with_explanation
    err = assert_raises(Zfp::PackerError) { Zfp::Packer.decode(legacy_v1([10, 20])) }
    assert_match(/0\.1\.0/, err.message)
    assert_match(/transposed/, err.message)
  end
end
