# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class PackedTest < Minitest::Test
  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
    @data   = (1..20).map(&:to_f)
    @packed = Zfp.pack(@data, type: :double, shape: [20], mode: :fixed_accuracy, tolerance: 0.01)
    @bytes  = @packed.to_str
  end

  def in_tmpdir
    Dir.mktmpdir("zfp") { |dir| yield File.join(dir, "data.zfp") }
  end

  # --- construction ---

  def test_pack_returns_a_packed
    assert_kind_of Zfp::Packed, @packed
  end

  def test_codec_pack_returns_a_packed
    codec = Zfp::Codec.new(type: :double, shape: [20], mode: :reversible)
    assert_kind_of Zfp::Packed, codec.pack(@data)
  end

  def test_new_from_string_bytes
    assert_equal @packed, Zfp::Packed.new(@bytes)
  end

  def test_new_rejects_bytes_that_are_not_a_pack
    assert_raises(Zfp::PackerError) { Zfp::Packed.new("not a pack") }
  end

  # --- String compatibility ---

  def test_to_str_returns_the_bytes
    assert_equal @bytes, @packed.to_str
    assert_equal @bytes, @packed.to_s
  end

  def test_bytesize
    assert_equal @bytes.bytesize, @packed.bytesize
    assert_operator @packed.bytesize, :>, 32
  end

  def test_bytes_are_frozen_and_independent_of_input
    mutable = @bytes.dup
    packed  = Zfp::Packed.new(mutable)
    mutable << "trailing"
    assert_equal @bytes, packed.to_str
    assert packed.to_str.frozen?
  end

  def test_equality_with_plain_string_and_hash_consistency
    assert_equal @packed, @bytes
    assert_equal @packed.hash, Zfp::Packed.new(@bytes).hash
    assert_equal 1, [@packed, Zfp::Packed.new(@bytes)].uniq.size
  end

  def test_string_apis_accept_a_packed_via_to_str
    in_tmpdir do |path|
      File.binwrite(path, @packed)
      assert_equal @bytes, File.binread(path)
    end
  end

  # --- header readers (no decompression) ---

  def test_type_shape_mode_params
    assert_equal :double, @packed.type
    assert_equal [20], @packed.shape
    assert_equal :fixed_accuracy, @packed.mode
    assert_in_delta 0.01, @packed.params[:tolerance], 1e-12
    refute @packed.numo?
  end

  def test_numo_flag_for_numo_input
    packed = Zfp.pack(Numo::DFloat.new(3, 4).seq, mode: :reversible)
    assert packed.numo?
    assert_equal [3, 4], packed.shape
    assert_equal({}, packed.params)
  end

  def test_inspect_summarises_header
    s = @packed.inspect
    assert_match(/type=:double/, s)
    assert_match(/shape=\[20\]/, s)
    assert_match(/mode=:fixed_accuracy/, s)
    assert_match(/tolerance=0\.01/, s)
    assert_match(/bytesize=#{@packed.bytesize}/, s)
  end

  # --- unpack ---

  def test_unpack_returns_original_data_within_tolerance
    back = @packed.unpack
    assert_equal 20, back.size
    assert_operator @data.zip(back).map { |a, b| (a - b).abs }.max, :<=, 0.01
  end

  def test_zfp_unpack_accepts_a_packed
    assert_equal @packed.unpack, Zfp.unpack(@packed)
  end

  def test_unpack_of_numo_pack_returns_numo
    na = Numo::DFloat.new(3, 4).seq
    result = Zfp.pack(na, mode: :reversible).unpack
    assert_kind_of Numo::DFloat, result
    assert_equal na.to_a, result.to_a
  end

  # --- save / load (issue #1) ---

  def test_save_writes_the_bytes_and_returns_the_path
    in_tmpdir do |path|
      assert_equal path, @packed.save(path)
      assert_equal @bytes, File.binread(path)
    end
  end

  def test_zfp_load_restores_a_packed_with_metadata_intact
    in_tmpdir do |path|
      @packed.save(path)
      loaded = Zfp.load(path)
      assert_kind_of Zfp::Packed, loaded
      assert_equal @packed, loaded
      assert_equal :fixed_accuracy, loaded.mode
      assert_equal @packed.unpack, loaded.unpack
    end
  end

  def test_packed_load_is_equivalent_to_zfp_load
    in_tmpdir do |path|
      @packed.save(path)
      assert_equal Zfp.load(path), Zfp::Packed.load(path)
    end
  end

  def test_save_load_roundtrip_preserves_numo_shape
    in_tmpdir do |path|
      Zfp.pack(Numo::DFloat.new(6, 7).seq, mode: :reversible).save(path)
      result = Zfp.load(path).unpack
      assert_equal [6, 7], result.shape
    end
  end

  def test_load_missing_file_raises_errno
    in_tmpdir { |path| assert_raises(Errno::ENOENT) { Zfp.load(path) } }
  end

  def test_load_of_non_zfp_file_raises_packer_error
    in_tmpdir do |path|
      File.binwrite(path, "this is not a zfp file at all, just text padding....")
      assert_raises(Zfp::PackerError) { Zfp.load(path) }
    end
  end

  def test_extension_constant
    assert_equal ".zfp", Zfp::Packed::EXTENSION
  end
end
