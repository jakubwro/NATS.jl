module NATS

using Revise
using Random
using Sockets
using StructTypes
using JSON3

import Base: show, close

const NATS_CLIENT_VERSION = "0.1.0"
const NATS_CLIENT_LANG = "julia"
const NATS_DEFAULT_HOST = "localhost"
const NATS_DEFAULT_PORT = 4222

include("protocol_data.jl")
include("parser.jl")
include("serializer.jl")
include("connection.jl")

export connect, ping, subscribe, subscribe, publish, payload

end
