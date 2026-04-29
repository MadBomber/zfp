# Installation

## Requirements

| Requirement | Version | Notes |
|---|---|---|
| Ruby | ≥ 3.0 | |
| libzfp | 1.0+ | native C library, installed separately |
| [ffi](https://github.com/ffi/ffi) | ~> 1.0 | installed automatically as a gem dependency |
| [numo-narray](https://github.com/ruby-numo/numo-narray) | any | optional — loaded automatically if present |

The gem uses [ruby-ffi](https://github.com/ffi/ffi), which means there is **no native compilation step**. `gem install` is instant; the library loads at runtime.

---

## Step 1 — Install libzfp

Install the native ZFP library using [upkg](https://github.com/seuros/upkg):

```bash
upkg install zfp
```

Alternatively, if you prefer Homebrew on macOS:

```bash
brew install zfp
```

Or on Debian/Ubuntu:

```bash
apt-get install libzfp-dev
```

Verify the library is visible to the linker:

```bash
ruby -e "require 'ffi'; extend FFI::Library; ffi_lib 'zfp'; puts 'OK'"
```

---

## Step 2 — Add the gem

### With Bundler (recommended)

```bash
bundle add zfp
```

Or add the line to your `Gemfile` manually:

```ruby
gem "zfp"
```

Then run:

```bash
bundle install
```

### Without Bundler

```bash
gem install zfp
```

---

## Optional — Numo::NArray

If you want to compress [Numo::NArray](https://github.com/ruby-numo/numo-narray) arrays directly (auto-detecting type and shape), install numo-narray:

```bash
gem install numo-narray
# or: bundle add numo-narray
```

The `zfp` gem detects Numo at runtime — no configuration required. If Numo is not loaded, all Numo-related features are silently unavailable, and plain Ruby Arrays work as normal.

---

## Verifying the Installation

```ruby
require "zfp"

data  = (1..100).map { |i| i * 1.5 }
bytes = Zfp.compress(data, type: :double, shape: [100], mode: :reversible)
back  = Zfp.decompress(bytes, type: :double, shape: [100], mode: :reversible)

puts data == back   # => true
puts Zfp::VERSION   # => 0.1.0
```

---

## Troubleshooting

### `Zfp::LibraryNotFound`

The gem raises `Zfp::LibraryNotFound` at require time if `libzfp` cannot be found.

**Check that libzfp is installed and on the library path:**

```bash
# macOS
ls /usr/local/lib/libzfp* /opt/homebrew/lib/libzfp* 2>/dev/null

# Linux
ldconfig -p | grep zfp
```

If the library is installed in a non-standard location, set `DYLD_LIBRARY_PATH` (macOS) or `LD_LIBRARY_PATH` (Linux) before running Ruby.

### Tests skip on systems without libzfp

The test suite auto-skips ZFP-dependent tests when `libzfp` is not found, so the suite is always safe to run in CI without the native library.
