module JetStream

import ..NATS

using Random
using JSON3

function validate_name(name::String)
    # ^[^.*>]+$
    # https://github.com/nats-io/jsm.go/blob/30c85c3d2258321d4a2ded882fe8561a83330e5d/schema_source/jetstream/api/v1/definitions.json#L445
    isempty(name) && error("Name is empty.")
    for c in name
        if c == '.' || c == '*' || c == '>'
            error("Name \"$name\" contains invalid character '$c'.")
        end
    end
    true
end

include("stream.jl")
include("consumer.jl")
include("keyvalue.jl")
include("show.jl")
include("convert.jl")

export StreamConfiguration, stream_create

end
