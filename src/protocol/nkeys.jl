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
