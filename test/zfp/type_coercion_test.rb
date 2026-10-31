# frozen_string_literal: true

require "test_helper"

class TypeCoercionTest < Minitest::Test
  def test_detect_type_returns_nil_for_ruby_array
    assert_nil Zfp::TypeCoercion.detect_type([1.0, 2.0])
  end

  def test_detect_type_returns_float_for_sfloat
    assert_equal :float, Zfp::TypeCoercion.detect_type(Numo::SFloat[1.0, 2.0])
  end

  def test_detect_type_returns_double_for_dfloat
    assert_equal :double, Zfp::TypeCoercion.detect_type(Numo::DFloat[1.0, 2.0])
  end

  def test_detect_type_returns_int32_for_int32
    assert_equal :int32, Zfp::TypeCoercion.detect_type(Numo::Int32[1, 2])
  end

  def test_detect_type_returns_int64_for_int64
    assert_equal :int64, Zfp::TypeCoercion.detect_type(Numo::Int64[1, 2])
  end

  def test_detect_type_raises_for_unsupported_numo_class
    assert_raises(Zfp::InvalidType) { Zfp::TypeCoercion.detect_type(Numo::UInt8[1, 2]) }
  end

  def test_detect_shape_returns_nil_for_ruby_array
    assert_nil Zfp::TypeCoercion.detect_shape([1.0, 2.0])
  end

  def test_detect_shape_returns_shape_for_numo
    na = Numo::DFloat.new(3, 4).fill(0)
    assert_equal [3, 4], Zfp::TypeCoercion.detect_shape(na)
  end

  def test_numo_predicate_false_for_ruby_array
    refute Zfp::TypeCoercion.numo?([1.0])
  end

  def test_numo_predicate_true_for_numo_array
    assert Zfp::TypeCoercion.numo?(Numo::DFloat[1.0])
  end

  def test_ensure_numo_is_a_no_op_when_numo_is_loaded
    assert_nil Zfp::TypeCoercion.ensure_numo!
  end

  { float: [1.5, 2.5, 3.5, 4.5], double: [1.5, 2.5, 3.5, 4.5],
    int32: [1, 2, 3, 4],          int64:  [1, 2, 3, 4] }.each do |type, data|
    define_method("test_ruby_array_#{type}_roundtrip") do
      ptr = Zfp::TypeCoercion.to_buffer(data, type)
      result = Zfp::TypeCoercion.from_buffer(ptr, type, [4], false)
      data.each_with_index { |v, i| assert_in_delta v, result[i], 0.001 }
    end
  end

  def test_numo_dfloat_roundtrip
    na = Numo::DFloat[1.5, 2.5, 3.5]
    ptr = Zfp::TypeCoercion.to_buffer(na, :double)
    result = Zfp::TypeCoercion.from_buffer(ptr, :double, [3], true)
    assert_kind_of Numo::DFloat, result
    assert_equal [1.5, 2.5, 3.5], result.to_a
  end

  def test_numo_sfloat_roundtrip
    na = Numo::SFloat[1.0, 2.0]
    ptr = Zfp::TypeCoercion.to_buffer(na, :float)
    result = Zfp::TypeCoercion.from_buffer(ptr, :float, [2], true)
    assert_kind_of Numo::SFloat, result
  end

  # --- to_buffer validation ---

  def test_to_buffer_with_matching_shape_succeeds
    ptr = Zfp::TypeCoercion.to_buffer([1.0, 2.0, 3.0, 4.0], :double, [2, 2])
    assert_equal 32, ptr.size
  end

  def test_to_buffer_raises_invalid_shape_when_count_differs
    err = assert_raises(Zfp::InvalidShape) { Zfp::TypeCoercion.to_buffer([1.0, 2.0], :double, [4]) }
    assert_match(/4 elements but data has 2/, err.message)
  end

  def test_to_buffer_raises_invalid_type_for_non_array_input
    assert_raises(Zfp::InvalidType) { Zfp::TypeCoercion.to_buffer("1.0 2.0", :double) }
  end

  def test_to_buffer_raises_invalid_type_for_unknown_type
    assert_raises(Zfp::InvalidType) { Zfp::TypeCoercion.to_buffer([1.0], :float128) }
  end

  def test_to_buffer_int32_rejects_floats
    err = assert_raises(Zfp::InvalidType) { Zfp::TypeCoercion.to_buffer([1.9, 2.7], :int32) }
    assert_match(/Integers/, err.message)
  end

  def test_to_buffer_int32_rejects_out_of_range
    assert_raises(Zfp::InvalidType) { Zfp::TypeCoercion.to_buffer([2**31], :int32) }
    assert_raises(Zfp::InvalidType) { Zfp::TypeCoercion.to_buffer([-2**31 - 1], :int32) }
  end

  def test_to_buffer_int64_rejects_out_of_range
    assert_raises(Zfp::InvalidType) { Zfp::TypeCoercion.to_buffer([2**63], :int64) }
  end

  def test_to_buffer_int_accepts_range_extremes
    Zfp::TypeCoercion.to_buffer([-2**31, 2**31 - 1], :int32)
    Zfp::TypeCoercion.to_buffer([-2**63, 2**63 - 1], :int64)
  end

  def test_to_buffer_double_accepts_integers
    ptr = Zfp::TypeCoercion.to_buffer([1, 2], :double)
    assert_equal [1.0, 2.0], Zfp::TypeCoercion.from_buffer(ptr, :double, [2], false)
  end
end
