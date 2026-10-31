## [Unreleased]

## [0.2.0] - 2026-10-31

### Fixed

- **Multi-dimensional data was handed to libzfp transposed** ([#2](https://github.com/MadBomber/zfp/issues/2)).
  `shape:` is row-major (Ruby Array / Numo order, last dimension fastest) but
  `shape[0]` was passed as zfp's `nx`, which is the fastest-varying dimension.
  Round-trips were still exact, but compression ratios and lossy accuracy on
  2-D/3-D/4-D data were badly degraded. The gem now reverses the shape
  internally; the public `shape:` contract is unchanged.
- **Shape is now validated against the data length.** A mismatch used to make
  libzfp read or write past the data buffer (silent garbage, or a bus error for
  large shapes). It now raises `Zfp::InvalidShape`.
- **Decompression no longer reads past the input.** libzfp's bitstream has no
  bounds checking; short or corrupt input is now copied into a zero-filled
  buffer of the worst-case stream size. Empty input raises
  `Zfp::DecompressionFailed`, and so does a truncated `:fixed_rate` stream,
  whose exact size is known.
- Integer types (`:int32`, `:int64`) now raise `Zfp::InvalidMode` for any mode
  other than `:reversible`, as documented. Previously lossy modes were silently
  applied.
- Integer data is validated: non-Integer elements or values outside the 32- or
  64-bit range raise `Zfp::InvalidType` instead of being truncated or wrapped.
- `numo: true` without numo-narray loaded raises `Zfp::NumoNotAvailable`
  instead of a bare `NameError`; the gem now tries to `require "numo/narray"`
  on demand.
- `Zfp.pack` accepts an explicit `numo:` keyword.

### Changed

- **Pack header magic bumped to `ZFP\x02`.** Multi-dimensional bytes packed by
  0.1.0 (`ZFP\x01`) were compressed with the transposed layout and are rejected
  with a clear `Zfp::PackerError`; 1-D 0.1.0 bytes are layout-identical and
  still unpack.
- Shape validation lives in `Zfp::Field.validate_shape!` and is shared by
  `Zfp::Codec`.

### Added

- **Save and load `.zfp` files** ([#1](https://github.com/MadBomber/zfp/issues/1)).
  `Zfp.pack` and `Codec#pack` now return a `Zfp::Packed` instead of a raw
  `String`. It converts to a `String` via `#to_str`, so Redis, `File.binwrite`,
  `Zfp.unpack` and friends keep working; code that indexed the result as a
  String (`packed[0, 4]`) needs `packed.to_str`. `Packed#save(path)` writes the
  file and `Zfp.load(path)` (alias `Packed.load`) reads it back with metadata
  intact. `Packed#type`, `#shape`, `#mode`, `#params`, `#numo?` and `#inspect`
  read the header without decompressing; `Packer.decode_header` backs them.
- `LICENSE` file (MIT) and gemspec license/metadata.

## [0.1.0] - 2026-04-28

- Initial release
