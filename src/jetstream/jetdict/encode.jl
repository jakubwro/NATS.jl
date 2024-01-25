

# Encoding must confirm to `validate_key`, so not url safe base64 is not allowed because of '+'

struct KeyEncoding{encoding} end

const JETDICT_KEY_ENCODING = [:none, :base64url]

encodekey(::KeyEncoding{:none}, key::String) = key
decodekey(::KeyEncoding{:none}, key::String) = key

encodekey(::KeyEncoding{:base64url}, key::String) = String(transcode(Base64Encoder(urlsafe = true), key))
decodekey(::KeyEncoding{:base64url}, key::String) = String(transcode(Base64Decoder(urlsafe = true), key))

function check_encoding_implemented(encoding::Symbol)
    hasmethod(encodekey, (KeyEncoding{encoding}, String)) || error("No `encodekey` implemented for $encoding encoding, allowed encodings: $(join(NATS.JetStream.JETDICT_KEY_ENCODING, ", "))")
    hasmethod(decodekey, (KeyEncoding{encoding}, String)) || error("No `decodekey` implemented for $encoding encoding, allowed encodings: $(join(NATS.JetStream.JETDICT_KEY_ENCODING, ", "))")
end