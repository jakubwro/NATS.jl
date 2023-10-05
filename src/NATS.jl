module NATS

using Revise
using Random
using Sockets
using StructTypes
using JSON3
using MbedTLS
using DocStringExtensions
using BufferedStreams
using Sodium
using Base64
using CodecBase

import Base: show, convert, close

export connect, ping, publish, subscribe, unsubscribe, payload, request, reply, header, headers, drain, isdrained

const NATS_CLIENT_VERSION = "0.1.0"
const NATS_CLIENT_LANG = "julia"

const MIME_PROTOCOL = MIME"application/nats"
const MIME_PAYLOAD  = MIME"application/nats-payload"
const MIME_HEADERS  = MIME"application/nats-headers"

const ERROR_THROTTLING_SECONDS = 5
const OUTBOX_SIZE = 10000000
const SOCKET_CONNECT_DELAYS = Base.ExponentialBackOff(n=1000, first_delay=0.5, max_delay=1)
const SUBSCRIPTION_CHANNEL_SIZE = 10000


include("protocol/protocol.jl")
include("connection/connection.jl")
include("pubsub/pubsub.jl")
include("reqreply/reqreply.jl")

function __init__()
    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        if exc.f == convert && length(argtypes) > 1
             # TODO: check if 2nd arg is Msg of Hmsg
             print(io, """
                       
                       To use `$(argtypes[1])` as parameter of subscription handler apropriate conversion from `$(argtypes[2])` must be provided.
                       ```
                       import Base: convert

                       function convert(::Type{$(argtypes[1])}, msg::Union{NATS.Msg, NATS.HMsg})
                           # Implement conversion logic here.
                       end

                       ```
                       """)
        elseif exc.f == show
            print(io, """
                       
                       Object of type `$(argtypes[3])` cannot be serialized into payload.
                       ```
                       import Base: show

                       function Base.show(io::IO, NATS.MIME_PROTOCOL, x::$(argtypes[3]))
                            # Write content to `io` here.
                        end

                       ```
                       """)
        end
    end
end

end
