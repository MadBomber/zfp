# Zfp::Packed

`Zfp::Packed` is what `Zfp.pack` and `Zfp::Codec#pack` return: the compressed payload behind a 32-byte header that records type, shape, mode, parameters, and whether the input was a `Numo::NArray`. Because everything needed to decompress travels with the bytes, a `Packed` is the unit for persistence and for passing arrays between processes without a sidecar schema.

```ruby
packed = Zfp.pack(prices, type: :double, shape: [252], mode: :fixed_accuracy, tolerance: 0.001)
# => #<Zfp::Packed type=:double shape=[252] mode=:fixed_accuracy tolerance=0.001 bytesize=664>
```

---

## Constructing

| Call | Returns |
|---|---|
| `Zfp.pack(data, ...)` / `codec.pack(data)` | a new `Packed` |
| `Zfp.load(path)` / `Zfp::Packed.load(path)` | the `Packed` stored in a file |
| `Zfp::Packed.new(bytes)` | wraps raw packed bytes you already hold (e.g. read from Redis) |

`Packed.new` validates the header and raises `Zfp::PackerError` if the bytes are not a pack this version can read. The bytes are copied and frozen.

---

## String compatibility

A `Packed` responds to `to_str` (and `to_s`), so Ruby's implicit conversion lets it stand in for a `String` almost everywhere: `File.binwrite(path, packed)`, `redis.set(key, packed)`, `socket.write(packed)`, `Zfp.unpack(packed)`. It also defines `==` against anything with `to_str`, so `packed == raw_bytes` is true when the bytes match.

What does **not** work is calling `String` methods directly on it: use `packed.to_str[0, 4]`, not `packed[0, 4]`. Code written against 0.1.0, where `pack` returned a `String`, may need that one change.

| Method | Returns |
|---|---|
| `to_str` / `to_s` | the frozen `String` of bytes |
| `bytesize` | header + payload length |
| `==` / `eql?` / `hash` | byte equality, usable as a Hash key |

---

## Header readers

These parse only the 32-byte header, so they cost nothing measurable and never touch libzfp.

```ruby
packed.type     # => :double
packed.shape    # => [252]
packed.mode     # => :fixed_accuracy
packed.params   # => { tolerance: 0.001 }   ({} for :reversible)
packed.numo?    # => false                  (true when unpack will return a Numo::NArray)
```

---

## `#unpack`

```ruby
packed.unpack → Array | Numo::NArray
```

Decompresses and returns the data: a flat Ruby `Array`, or a `Numo::NArray` of the recorded shape when `numo?` is true. Equivalent to `Zfp.unpack(packed)`.

**Raises:** `Zfp::NumoNotAvailable` if `numo?` is true and the numo-narray gem is not installed; `Zfp::DecompressionFailed` for an empty or truncated-fixed-rate payload.

---

## `#save`

```ruby
packed.save(path) → path
```

Writes the bytes to `path` in binary mode and returns the path. Use the `.zfp` extension by convention (`Zfp::Packed::EXTENSION`); nothing enforces it.

```ruby
Zfp.pack(matrix, mode: :reversible).save("closes-2026-10.zfp")
```

---

## `Packed.load` / `Zfp.load`

```ruby
Zfp.load(path)         → Zfp::Packed
Zfp::Packed.load(path) → Zfp::Packed
```

Reads a file written by `#save`. The result carries the original metadata; nothing is decompressed until `#unpack`, so you can check `shape` or `mode` first.

**Raises:** the filesystem's `Errno::*` errors (e.g. `Errno::ENOENT`), and `Zfp::PackerError` if the file is not a zfp pack or is a multi-dimensional pack written by gem 0.1.0.

```ruby
loaded = Zfp.load("closes-2026-10.zfp")
loaded.shape        # => [50, 252]
loaded.numo?        # => true
closes = loaded.unpack   # => Numo::DFloat[50, 252]
```

---

## Checkpointing example

```ruby
require "numo/narray"
require "zfp"

state = Numo::DFloat.new(1000, 1000).rand

Zfp.pack(state, mode: :fixed_accuracy, tolerance: 1e-9).save("step-042.zfp")

# ...later, in another process
state = Zfp.load("step-042.zfp").unpack   # Numo::DFloat[1000, 1000]
```

The pack header is little-endian and version-tagged, so it reads the same on any machine. libzfp's payload uses 64-bit stream words and should exchange between platforms with the same word size, but cross-platform loading has not been verified by this gem's tests. A `.zfp` file is **not** readable by the `zfp` command-line tool or other zfp bindings, which expect zfp's own header or none.
