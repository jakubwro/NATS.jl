### NATS.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file aggregates all files of NATS.jl package.
#
### Code:

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
using CodecBase

import Base: show, convert, close, put!, take!

export connect, ping, publish, subscribe, unsubscribe, payload, request, reply, header, headers, drain, isdrained
export NATSChannel

const NATS_CLIENT_VERSION = "0.1.0"
const NATS_CLIENT_LANG = "julia"

const MIME_PROTOCOL = MIME"application/nats"
const MIME_PAYLOAD  = MIME"application/nats-payload"
const MIME_HEADERS  = MIME"application/nats-headers"

const RECONNECT_DELAYS = Base.ExponentialBackOff(n=220752000000000000, first_delay=0.0001, max_delay=1) # 7 bilion years.
const SUBSCRIPTION_CHANNEL_SIZE = 10000000
const SUBSCRIPTION_ERROR_THROTTLING_SECONDS = 5.0
const REQUEST_TIMEOUT_SECONDS = 5.0 # TODO: add to ENV

# If set to true messages will be enqueued when connection lost, otherwise exception will be thrown.
const SEND_ENQUEUE_WHEN_NOT_CONNECTED = false
const INVOKE_LATEST_CONVERSIONS = false

include("protocol/protocol.jl")
include("connection/connection.jl")
include("pubsub/pubsub.jl")
include("reqreply/reqreply.jl")
include("interrupts.jl")

function __init__()

    start_interrupt_handler()

    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        if exc.f == convert && length(argtypes) > 1
             # TODO: check if 2nd arg is Msg of Hmsg
             print(io, """
                       
                       To use `$(argtypes[1])` as parameter of subscription handler apropriate conversion from `$(argtypes[2])` must be provided.
                       ```
                       import Base: convert

                       function convert(::Type{$(argtypes[1])}, msg::NATS.Msg)
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
