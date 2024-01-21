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
using ScopedValues
using URIs

import Base: show, convert

export NATSError
export connect, reconnect, ping, drain
export payload, header, headers
export publish, subscribe, unsubscribe, next
export request, reply
export with_connection

const DEFAULT_HOST = "localhost"
const DEFAULT_PORT = "4222"
const DEFAULT_CONNECT_URL = "nats://$(DEFAULT_HOST):$(DEFAULT_PORT)"
const CLIENT_VERSION = "0.1.0"
const CLIENT_LANG = "julia"

const MIME_PROTOCOL = MIME"application/nats"
const MIME_PAYLOAD  = MIME"application/nats-payload"
const MIME_HEADERS  = MIME"application/nats-headers"

# Granular reconnect retries configuration
#TODO: ADR-40 says it should be 3.
const DEFAULT_RECONNECT_RETRIES = 220752000000000000 # 7 bilion years.
const DEFAULT_RECONNECT_FIRST_DELAY = 0.1
const DEFAULT_RECONNECT_MAX_DELAY = 5.0
const DEFAULT_RECONNECT_FACTOR = 5.0
const DEFAULT_RECONNECT_JITTER = 0.1

const DEFAULT_SEND_BUFFER_LIMIT_BYTES = 2 * 2^20 # 2 MB
const DEFAULT_PING_INTERVAL_SECONDS = 2.0 * 60.0
const DEFAULT_MAX_PINGS_OUT = 2
const DEFAULT_RETRY_ON_INIT_FAIL = false
const DEFAULT_IGNORE_ADVERTISED_SERVERS = false
const DEFAULT_RETAIN_SERVERS_ORDER = false
const DEFAULT_ENQUEUE_WHEN_DISCONNECTED = true
const DEFAULT_SUBSCRIPTION_CHANNEL_SIZE = 512 * 1024
const DEFAULT_SUBSCRIPTION_ERROR_THROTTLING_SECONDS = 5.0
const DEFAULT_REQUEST_TIMEOUT_SECONDS = 5.0
const DEFAULT_DRAIN_TIMEOUT_SECONDS = 5.0
const DEFAULT_DRAIN_POLL_INTERVAL_SECONDS = 0.2

# If set to true messages will be enqueued when connection lost, otherwise exception will be thrown.
const INVOKE_LATEST_CONVERSIONS = false # TODO: use this in code

include("protocol/protocol.jl")
include("connection/connection.jl")
include("pubsub/pubsub.jl")
include("reqreply/reqreply.jl")
include("experimental/experimental.jl")
include("interrupts.jl")
include("jetstream/jetstream.jl")

function __init__()
    # start_interrupt_handler()
end

end
