# frozen_string_literal: true

module Zfp
  class Packed
    def initialize(bytes)
      @bytes = bytes.freeze
    end

    def to_str
      @bytes
    end

    def bytesize
      @bytes.bytesize
    end

    def save(path)
      File.binwrite(path, @bytes)
    end

    def unpack
      Zfp.unpack(self)
    end
  end
end
