### nkeys.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains implementations nkeys signingature which is one of methods of authentication used by NATS protocol.
#
### Code:

const PUBLIC_KEY_LENGTH = Sodium.LibSodium.crypto_sign_ed25519_PUBLICKEYBYTES
const SECRET_KEY_LENGTH = Sodium.LibSodium.crypto_sign_ed25519_SECRETKEYBYTES
const SIGNATURE_LENGTH = Sodium.LibSodium.crypto_sign_ed25519_BYTES

"""
    sign(nonce::String, nkey_seed::String) -> String

Sign a server challenge `nonce` with a private `nkey_seed` (`"S..."`) using
Ed25519. Returns the URL-safe Base64-encoded detached signature sent in the
`CONNECT` protocol message.
"""
function sign(nonce::String, nkey_seed::String)
    public_key =  Vector{Cuchar}(undef, PUBLIC_KEY_LENGTH)
    secret_key =  Vector{Cuchar}(undef, SECRET_KEY_LENGTH)
    raw_seed = _decode_seed(nkey_seed)    
    errno = Sodium.LibSodium.crypto_sign_ed25519_seed_keypair(public_key, secret_key, raw_seed)
    errno == 0 || error("Cannot get key pair from nkey seed.")
    signed_message_length = Ref{UInt64}(0)
    signed_message = Vector{Cuchar}(undef, SIGNATURE_LENGTH)
    errno = Sodium.LibSodium.crypto_sign_ed25519_detached(signed_message, signed_message_length, nonce, sizeof(nonce), secret_key)
    errno == 0 || error("Cannot sign nonce.")
    @assert signed_message_length[] == SIGNATURE_LENGTH "Unexpected signature length."
    signature = transcode(Base64Encoder(urlsafe = true), signed_message)
    String(rstrip(==('='), String(signature)))
end

function _decode(encoded::String)
    padding_length = mod(8 - mod(length(encoded), 8), 8)
    raw = transcode(Base32Decoder(), encoded * repeat("=", padding_length))
	length(raw) < 4 && error("Invalid length of decoded nkey.")
    crc_bytes = raw[end-1:end]
    data_bytes = raw[begin:end-2]
    crc = only(reinterpret(UInt16, crc_bytes))
    crc == crc16(data_bytes) || error("Invalid nkey CRC16 sum.")
	data_bytes
end

# Inverse of `_decode`: append the CRC16 (little-endian, as `_decode`
# reads it) and Base32-encode without padding.
function _encode(data_bytes::Vector{UInt8})
    crc = crc16(data_bytes)
    full = vcat(data_bytes, UInt8[crc % UInt8, (crc >> 8) % UInt8])
    encoded = transcode(Base32Encoder(), full)
    String(rstrip(==('='), String(encoded)))
end

# RFC 4648 Base32 alphabet: the nth character (0-based) is the 5-bit
# value n. An nkey's leading character therefore encodes the top 5 bits
# of its prefix byte (prefix_byte == value << 3).
const _BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

const NKEY_SEED_PREFIXES = ['S'] # seed
const NKEY_PUBLIC_PREFIXES = ['N', 'C', 'O', 'A', 'U', 'X'] # server, cluster, operator, account, user, curve
const NKEY_PREFIXES = ['S', 'P', 'N', 'C', 'O', 'A', 'U', 'X'] # seed, private, server, cluster, operator, account, user, curve

function _decode_seed(seed)
    # https://github.com/nats-io/nkeys/blob/3e454c8ca12e8e8a15d4c058d380e1ec31399597/strkey.go#L172
    seed[1] in NKEY_PUBLIC_PREFIXES && error("Public nkey provided instead of private nkey seed, it should start with character '$(NKEY_SEED_PREFIXES...)'.")
    seed[1] in NKEY_SEED_PREFIXES || error("Invalid nkey seed prefix, expected one of: $NKEY_SEED_PREFIXES.")
    seed[2] in NKEY_PUBLIC_PREFIXES || error("Invalid public nkey prefix, expected one of: $NKEY_PUBLIC_PREFIXES.")
    raw = _decode(seed)
	raw[3:end]
end

"""
    public_key(nkey_seed::String) -> String

Derive the public NKey string (e.g. `"U..."` for a user seed) from a
private NKey `nkey_seed` (`"S..."`). This is the identity the server
authenticates via [`sign`](@ref); useful for principal mapping and audit
without exposing the seed. The role is taken from the seed's second
character, so a user seed yields a `U` key, an account seed an `A` key,
and so on.
"""
function public_key(nkey_seed::String)
    raw_seed = _decode_seed(nkey_seed)
    public_key_bytes = Vector{Cuchar}(undef, PUBLIC_KEY_LENGTH)
    secret_key = Vector{Cuchar}(undef, SECRET_KEY_LENGTH)
    errno = Sodium.LibSodium.crypto_sign_ed25519_seed_keypair(public_key_bytes, secret_key, raw_seed)
    errno == 0 || error("Cannot derive key pair from nkey seed.")
    # The seed's 2nd character is the public role letter; its prefix byte
    # is that Base32 value shifted into the top 5 bits.
    role = nkey_seed[2]
    idx = findfirst(==(role), _BASE32_ALPHABET)
    isnothing(idx) && error("Invalid nkey role prefix '$role'.")
    prefix_byte = UInt8((idx - 1) << 3)
    _encode(vcat(UInt8[prefix_byte], UInt8.(public_key_bytes)))
end
