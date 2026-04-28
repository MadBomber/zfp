# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  def test_error_inherits_from_standard_error
    assert_includes Zfp::Error.ancestors, StandardError
  end

  {
    Zfp::LibraryNotFound     => Zfp::Error,
    Zfp::InvalidType         => Zfp::Error,
    Zfp::InvalidMode         => Zfp::Error,
    Zfp::InvalidShape        => Zfp::Error,
    Zfp::InvalidParams       => Zfp::Error,
    Zfp::CompressionFailed   => Zfp::Error,
    Zfp::DecompressionFailed => Zfp::Error,
    Zfp::PackerError         => Zfp::Error
  }.each do |subclass, parent|
    define_method("test_#{subclass.name.split("::").last.downcase}_inherits_from_error") do
      assert_includes subclass.ancestors, parent
    end
  end
end
