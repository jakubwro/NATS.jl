include("structs.jl")
include("parser.jl")
include("payload.jl")
include("headers.jl")
include("convert.jl")
include("show.jl")
const Message = Union{Msg, HMsg}
