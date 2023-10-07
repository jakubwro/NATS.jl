# NATS authentication

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
	length(raw) < 4 && error("Invalid length of encoded seed.")
    # ntoh, hton
    # crc = raw[end-1:end]
    # TODO: validate CRC16 sum of raw[begin:end-2] vs crc
	raw[begin:end-2]
end


function _decode_seed(seed) 
    raw = _decode(seed)
	
    # TODO: validate prefixes: https://github.com/nats-io/nkeys/blob/3e454c8ca12e8e8a15d4c058d380e1ec31399597/strkey.go#L172

	raw[3:end]
end