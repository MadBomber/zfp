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
end
