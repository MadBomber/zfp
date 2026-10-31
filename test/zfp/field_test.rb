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

  # --- validate_shape! (class method, shared with Codec) ---

  def test_validate_shape_accepts_1_to_4_positive_dims
    [[1], [2, 3], [2, 3, 4], [2, 3, 4, 5]].each { |s| Zfp::Field.validate_shape!(s) }
  end

  def test_validate_shape_rejects_non_array
    assert_raises(Zfp::InvalidShape) { Zfp::Field.validate_shape!(16) }
  end

  def test_validate_shape_rejects_zero_dimension
    assert_raises(Zfp::InvalidShape) { Zfp::Field.validate_shape!([0, 4]) }
  end

  def test_validate_shape_rejects_non_integer_dimension
    assert_raises(Zfp::InvalidShape) { Zfp::Field.validate_shape!([4.0]) }
  end

  # --- dimension order (issue #2) ---
  # Ruby/Numo shape is row-major (last dimension fastest); libzfp's nx is the
  # fastest-varying dimension, so the shape must be reversed for libzfp.

  def test_zfp_dimensions_reverses_shape
    assert_equal [252, 50], Zfp::Field.zfp_dimensions([50, 252])
    assert_equal [4, 3, 2], Zfp::Field.zfp_dimensions([2, 3, 4])
    assert_equal [16],      Zfp::Field.zfp_dimensions([16])
  end

  def test_row_major_shape_compresses_better_than_transposed_shape
    # 100 rows x 120 cols; every row is the same linear ramp, so the fastest
    # varying (last) axis is smooth. Described correctly, zfp exploits that.
    rows, cols = 100, 120
    data = Array.new(rows) { Array.new(cols) { |x| x.to_f } }.flatten
    correct    = Zfp.compress(data, type: :float, shape: [rows, cols], mode: :reversible)
    transposed = Zfp.compress(data, type: :float, shape: [cols, rows], mode: :reversible)
    assert_operator correct.bytesize, :<, transposed.bytesize / 2,
      "row-major shape should compress at least 2x better than the transposed shape"
  end

  def test_row_major_3d_compresses_better_than_transposed
    data = Array.new(10) { Array.new(100) { Array.new(120) { |x| x.to_f } } }.flatten
    correct    = Zfp.compress(data, type: :float, shape: [10, 100, 120], mode: :reversible)
    transposed = Zfp.compress(data, type: :float, shape: [120, 100, 10], mode: :reversible)
    assert_operator correct.bytesize, :<, transposed.bytesize / 2
  end
end
