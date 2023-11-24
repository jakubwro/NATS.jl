include("structs.jl")

const Message = Union{Msg, HMsg}

include("parser.jl")
include("parser4.jl")
include("payload.jl")
include("headers.jl")
include("convert.jl")
include("show.jl")
include("crc16.jl")
include("nkeys.jl")
