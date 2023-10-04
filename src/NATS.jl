module NATS

using Revise
using Random
using Sockets
using StructTypes
using JSON3
using MbedTLS
using DocStringExtensions
using BufferedStreams

import Base: show, convert, close

export connect, ping, publish, subscribe, unsubscribe, payload, request, reply, header, headers, drain, isdrained

const NATS_CLIENT_VERSION = "0.1.0"
const NATS_CLIENT_LANG = "julia"
const NATS_HOST = get(ENV, "NATS_HOST", "localhost")
const NATS_PORT = parse(Int, get(ENV, "NATS_PORT", "4222"))

# Server might be configured to require client TLS certificate.
const NATS_TLS_CERT_PATH = get(ENV, "NATS_TLS_CERT_PATH", nothing)
const NATS_TLS_KEY_PATH = get(ENV, "NATS_TLS_KEY_PATH", nothing)

const ERROR_THROTTLING_SECONDS = 5
const DEFAULT_CONNECT_OPTIONS = (
    verbose= parse(Bool, get(ENV, "NATS_VERBOSE", "false")),
    pedantic = parse(Bool, get(ENV, "NATS_PEDANTIC", "false")),
    tls_required = parse(Bool, get(ENV, "NATS_TLS_REQUIRED", "false")),
    auth_token = get(ENV, "NATS_AUTH_TOKEN", nothing),
    user = get(ENV, "NATS_USER", nothing),
    pass = get(ENV, "NATS_PASS", nothing),
    name = nothing,
    lang = NATS_CLIENT_LANG,
    version = NATS_CLIENT_VERSION,
    protocol = 1,
    echo = nothing,
    sig = nothing,
    jwt = get(ENV, "NATS_JWT", nothing),
    no_responders = true,
    headers = true,
    nkey = get(ENV, "NATS_NKEY", nothing)
)
const OUTBOX_SIZE = 10000000
const SOCKET_CONNECT_DELAYS = Base.ExponentialBackOff(n=1000, first_delay=0.5, max_delay=1)
const SUBSCRIPTION_CHANNEL_SIZE = 10000

const MIME_PROTOCOL = MIME"application/nats"
const MIME_PAYLOAD  = MIME"application/nats-payload"
const MIME_HEADERS  = MIME"application/nats-headers"

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
