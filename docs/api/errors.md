# Errors

All exceptions raised by the `zfp` gem are subclasses of `Zfp::Error`, which is itself a subclass of `StandardError`. This lets you rescue them individually or catch all gem errors with a single `rescue Zfp::Error`.

---

## Hierarchy

```
StandardError
└── Zfp::Error
    ├── Zfp::LibraryNotFound
    ├── Zfp::InvalidType
    ├── Zfp::InvalidMode
    ├── Zfp::InvalidShape
    ├── Zfp::InvalidParams
    ├── Zfp::CompressionFailed
    ├── Zfp::DecompressionFailed
    └── Zfp::PackerError
```

---

## `Zfp::LibraryNotFound`

Raised at `require "zfp"` time if `libzfp` cannot be found on the system.

**When:** The FFI layer fails to load the native `zfp` library.

**Resolution:** Install `libzfp` — see [Installation](../installation.md).

```ruby
rescue Zfp::LibraryNotFound => e
  warn "ZFP not available: #{e.message}"
  # Fall back to uncompressed storage
```

---

## `Zfp::InvalidType`

Raised when `type:` is not one of the four supported symbols.

**Valid values:** `:float`, `:double`, `:int32`, `:int64`

```ruby
Zfp.compress(data, type: :complex, shape: [10], mode: :reversible)
# => Zfp::InvalidType: Unknown type: :complex. Valid: [:float, :double, :int32, :int64]
```

Also raised when a `Numo::NArray` subtype is not supported (e.g. `Numo::UInt8`).

---

## `Zfp::InvalidMode`

Raised when `mode:` is not one of the four supported symbols.

**Valid values:** `:reversible`, `:fixed_rate`, `:fixed_precision`, `:fixed_accuracy`

```ruby
Zfp.compress(data, type: :double, shape: [10], mode: :lz4)
# => Zfp::InvalidMode: Unknown mode: :lz4. Valid: [:fixed_rate, :fixed_precision, :fixed_accuracy, :reversible]
```

---

## `Zfp::InvalidShape`

Raised when `shape:` is not a valid array of 1–4 positive integers.

```ruby
Zfp.compress(data, type: :double, shape: [],        mode: :reversible)
# => Zfp::InvalidShape: shape must be Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [0, 100],  mode: :reversible)
# => Zfp::InvalidShape: shape must be Array of 1–4 positive integers

Zfp.compress(data, type: :double, shape: [2,2,2,2,2], mode: :reversible)
# => Zfp::InvalidShape: shape must be Array of 1–4 positive integers
```

---

## `Zfp::InvalidParams`

Raised when a mode-specific parameter is missing, not the right type, or out of range.

```ruby
# fixed_rate requires rate: (Float > 0)
Zfp.compress(data, type: :double, shape: [100], mode: :fixed_rate)
# => Zfp::InvalidParams: fixed_rate requires rate: (Float > 0)

# fixed_precision requires precision: (Integer > 0)
Zfp.compress(data, type: :double, shape: [100], mode: :fixed_precision, precision: 0)
# => Zfp::InvalidParams: fixed_precision requires precision: (Integer > 0)

# fixed_accuracy requires tolerance: (Float > 0)
Zfp.compress(data, type: :double, shape: [100], mode: :fixed_accuracy, tolerance: -1.0)
# => Zfp::InvalidParams: fixed_accuracy requires tolerance: (Float > 0)
```

---

## `Zfp::CompressionFailed`

Raised when `libzfp` returns 0 bytes written during compression.

This should not happen under normal conditions. It typically indicates a bug in the gem, a corrupt `libzfp` build, or a shape/type mismatch.

```ruby
rescue Zfp::CompressionFailed => e
  warn "ZFP compression failed: #{e.message}"
```

---

## `Zfp::DecompressionFailed`

Raised when `libzfp` returns 0 bytes read during decompression.

**Common causes:**

- Wrong `type:`, `shape:`, or `mode:` on decompress (must match compress)
- Wrong mode params (e.g. different `tolerance:` than used during compression)
- Corrupt or truncated compressed bytes

```ruby
rescue Zfp::DecompressionFailed => e
  warn "ZFP decompression failed — check that type/shape/mode match: #{e.message}"
```

---

## `Zfp::PackerError`

Raised when `Zfp.unpack` receives a byte string with a corrupt or missing header.

**Common causes:**

- Truncated bytes (less than 32 bytes)
- Wrong magic bytes (data was not produced by `pack`)
- Bit-flip or storage corruption

```ruby
rescue Zfp::PackerError => e
  warn "Corrupt ZFP pack header: #{e.message}"
```

---

## Catching All Gem Errors

```ruby
begin
  packed   = Zfp.pack(data, type: :double, shape: [n], mode: :reversible)
  restored = Zfp.unpack(packed)
rescue Zfp::Error => e
  # Covers LibraryNotFound, InvalidType, CompressionFailed, PackerError, etc.
  Rails.logger.error("ZFP error: #{e.class} — #{e.message}")
end
```
