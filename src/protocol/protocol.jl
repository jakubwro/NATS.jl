include("structs.jl")

const Message = Union{Msg, HMsg}

include("parser.jl")
include("payload.jl")
include("headers.jl")
include("convert.jl")
include("show.jl")
include("nkeys.jl")
