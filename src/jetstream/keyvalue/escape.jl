

const JETDICT_KEY_ENCODING = [:none, :base64]

function encodekey(key::String, encoding::Symbol)
    if encoding == :none
        key
    elseif encoding == :base64
        base64encode(key)
    else
        error("Unknown key encoding $encoding")
    end
end

function decodekey(key::String, encoding::Symbol)
    if encoding == :none
        key
    elseif encoding == :base64
        String(base64decode(key))
    else
        error("Unknown key encoding $encoding")
    end
end