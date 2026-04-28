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

  def test_raises_packer_error_for_wrong_magic
    bad = "BAAD" + ("\x00" * 28) + RAW_BYTES
    err = assert_raises(Zfp::PackerError) { Zfp::Packer.decode(bad) }
    assert_match(/magic/, err.message)
  end

  def test_raises_packer_error_for_truncated_header
    err = assert_raises(Zfp::PackerError) { Zfp::Packer.decode("ZFP\x01\x00") }
    assert_match(/truncated/, err.message)
  end
end
