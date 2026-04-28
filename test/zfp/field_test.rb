# frozen_string_literal: true

require "test_helper"

class FieldTest < Minitest::Test
  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
    @data   = [1.0, 2.0, 3.0, 4.0]
    @buffer = Zfp::TypeCoercion.to_buffer(@data, :double)
  end

  def test_1d_allocates_without_error
    Zfp::Field.new(:double, [4], @buffer).free
  end

  def test_1d_exposes_zfp_type_int
    field = Zfp::Field.new(:double, [4], @buffer)
    assert_equal Zfp::FFI::ZFP_TYPE_DOUBLE, field.zfp_type_int
    field.free
  end

  def test_1d_exposes_shape
    field = Zfp::Field.new(:double, [4], @buffer)
    assert_equal [4], field.shape
    field.free
  end

  def test_1d_pointer_is_not_null
    field = Zfp::Field.new(:double, [4], @buffer)
    refute field.pointer.null?
    field.free
  end

  def test_1d_frees_without_error
    field = Zfp::Field.new(:double, [4], @buffer)
    field.free
  end

  def test_2d_shape
    buf   = Zfp::TypeCoercion.to_buffer([1.0] * 6, :double)
    field = Zfp::Field.new(:double, [2, 3], buf)
    assert_equal [2, 3], field.shape
    field.free
  end

  def test_4d_shape
    buf   = Zfp::TypeCoercion.to_buffer([0.0] * 16, :float)
    field = Zfp::Field.new(:float, [2, 2, 2, 2], buf)
    assert_equal [2, 2, 2, 2], field.shape
    field.free
  end

  def test_raises_invalid_shape_for_0_dimensions
    assert_raises(Zfp::InvalidShape) { Zfp::Field.new(:double, [], @buffer) }
  end

  def test_raises_invalid_shape_for_5_dimensions
    assert_raises(Zfp::InvalidShape) { Zfp::Field.new(:double, [1, 1, 1, 1, 1], @buffer) }
  end
end
