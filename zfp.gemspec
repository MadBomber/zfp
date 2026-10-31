require_relative "lib/zfp/version"

Gem::Specification.new do |spec|
  spec.name    = "zfp"
  spec.version = Zfp::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email   = ["dvanhoozer@gmail.com"]

  spec.summary     = "Ruby FFI bindings for the ZFP floating-point compression library"
  spec.description = <<~DESC
    Compress and decompress arrays of float/double/int32/int64 in 1-4
    dimensions using ZFP's fixed-rate, fixed-precision, fixed-accuracy,
    or lossless reversible modes. Accepts Ruby Array and Numo::NArray.
  DESC

  spec.homepage    = "https://github.com/madbomber/zfp"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata = {
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => spec.homepage,
    "changelog_uri"     => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://madbomber.github.io/zfp",
    "bug_tracker_uri"   => "#{spec.homepage}/issues"
  }

  spec.files = Dir["lib/**/*", "sig/**/*", "README.md", "CHANGELOG.md", "LICENSE"]

  spec.add_dependency "ffi", "~> 1.0"

  spec.add_development_dependency "numo-narray"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "debug_me"
end
