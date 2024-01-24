
const KV_STREAM_NAME_PREFIX = "KV_"

function validate_key(key::String)
    length(key) <= 3000 || error("Key is too long.")
    isempty(key) && error("Key is an empty string.")
    first(key) == '.' && error("Key \"$key\" starts with '.'")
    last(key) == '.' && error("Key \"$key\" ends with '.'")
    for c in key
        is_valid = isdigit(c) || isletter(c) || c in [ '-', '/', '_', '=', '.' ]
        !is_valid && error("Key \"$key\" contains invalid character '$c'.")
    end
    true
end

include("manage.jl")
include("watch.jl")
include("escape.jl")
include("jetdict.jl")