abstract type ApiResponse end

@kwdef struct ApiError <: Exception
    "HTTP like error code in the 300 to 500 range"
    code::Int64
    "A human friendly description of the error"
    description::Union{String, Nothing} = nothing
    "The NATS error code unique to each kind of error"
    err_code::Union{Int64, Nothing} = nothing
end

struct ApiResult <: ApiResponse
    success::Bool
end

struct IterableResponse
    total::Int64
    offset::Int64
    limit::Int64
end

include("stream.jl")
include("consumer.jl")
include("errors.jl")
include("validate.jl")
include("show.jl")
include("convert.jl")
include("call.jl")
