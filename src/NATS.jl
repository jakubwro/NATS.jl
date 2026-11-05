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

using Random
using Reseau
using StructTypes
using JSON3
using DocStringExtensions
using Sodium
using CodecBase
using ScopedValues
using URIs
using Dates

import Base: show, convert

export NATSError
export connect, reconnect, ping, drain
export payload, header, headers
export publish, subscribe, unsubscribe, next
export request, reply
export with_connection
export JetStream

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
const DEFAULT_ENQUEUE_WHEN_DISCONNECTED = true # If set to true messages will be enqueued when connection lost, otherwise exception will be thrown.
const DEFAULT_SUBSCRIPTION_CHANNEL_SIZE = 512 * 1024
const DEFAULT_SUBSCRIPTION_ERROR_THROTTLING_SECONDS = 5.0
const DEFAULT_REQUEST_TIMEOUT_SECONDS = 5.0
const DEFAULT_REQUEST_STOP_ON_STATUS = 400:599 # Every error status, includes 503 sent by the server when there are no responders.
const DEFAULT_DRAIN_TIMEOUT_SECONDS = 5.0
const DEFAULT_DRAIN_POLL_INTERVAL_SECONDS = 0.2

const INVOKE_LATEST_CONVERSIONS = false # TODO: use this in code

include("protocol/protocol.jl")
include("connection/connection.jl")
include("pubsub/pubsub.jl")
include("reqreply/reqreply.jl")
include("experimental/experimental.jl")
include("jetstream/JetStream.jl")

precompile(Tuple{typeof(NATS.init_protocol), NATS.Connection, String, ConnectOptions})
# `init_protocol` copies the options, `reconnect_delays` can be a vector.
precompile(Tuple{typeof(Base.deepcopy_internal), String, Base.IdDict{Any, Any}})
precompile(Tuple{typeof(Base.deepcopy_internal), Array{Float64, 1}, Base.IdDict{Any, Any}})
precompile(Tuple{typeof(NATS.connect)})
# Keyword arguments without a url.
precompile(Tuple{Type{NamedTuple{(:retry_on_init_fail,), T} where T<:Tuple}, Tuple{Bool}})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:retry_on_init_fail,), Tuple{Bool}}, typeof(NATS.connect)})
precompile(Tuple{typeof(NATS.wait_for_send_buffer_space), NATS.Connection, Float64})
precompile(Tuple{typeof(NATS.reconnect_controller), NATS.Connection, IOBuffer, TCP.Conn, TCP.Conn, ConnectOptions})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:timeout,), Tuple{Float64}}, typeof(NATS.request), NATS.Connection, String})
precompile(Tuple{typeof(NATS.as_option), Type{Union{Base.ExponentialBackOff, Array{Float64, 1}}}, Array{Int64, 1}})
precompile(Tuple{typeof(NATS.as_option), Type{Float64}, Int64})
precompile(Tuple{typeof(NATS.as_option), Type{Float64}, Dates.Second})
precompile(Tuple{typeof(NATS.as_option), Type{Float64}, Dates.Millisecond})
precompile(Tuple{typeof(NATS.as_option), Type{Union{Base.ExponentialBackOff, Array{Float64, 1}}}, UnitRange{Int64}})
precompile(Tuple{typeof(NATS.process), NATS.Connection, NATS.Ok})
# Task bodies are closures, whose names differ between Julia versions, so they are precompiled through `spawn_task`.
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.reconnect_controller), NATS.Connection, IOBuffer, TCP.Conn, TCP.Conn, ConnectOptions})
precompile(Tuple{typeof(NATS.receiver), NATS.Connection, TCP.Conn})
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.receiver), NATS.Connection, TCP.Conn})
precompile(Tuple{typeof(NATS.sendloop), NATS.Connection, TCP.Conn, IOBuffer})
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.sendloop), NATS.Connection, TCP.Conn, IOBuffer})
precompile(Tuple{typeof(NATS.ping_loop), NATS.Connection, Float64, Int64, Int64})
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.ping_loop), NATS.Connection, Float64, Int64, Int64})
precompile(Tuple{Type{NamedTuple{(:timeout,), T} where T<:Tuple}, Tuple{Int64}})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:timeout,), Tuple{Int64}}, typeof(NATS.request), NATS.Connection, String})
precompile(Tuple{typeof(Random.randstring), Random.MersenneTwister, Int64})
precompile(Tuple{Type{NamedTuple{(:should_wait,), T} where T<:Tuple}, Tuple{Bool}})
precompile(Tuple{typeof(NATS.process), NATS.Connection, NATS.Info})
# The initial connect failed with `retry_on_init_fail`, so there are no streams yet.
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:retry_on_init_fail,), Tuple{Bool}}, typeof(NATS.connect), String})
precompile(Tuple{typeof(NATS.reconnect_controller), NATS.Connection, IOBuffer, Nothing, Nothing, ConnectOptions})
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.reconnect_controller), NATS.Connection, IOBuffer, Nothing, Nothing, ConnectOptions})
# TLS connections read and write through `TLS.Conn`.
precompile(Tuple{typeof(NATS.reconnect_controller), NATS.Connection, IOBuffer, TLS.Conn, TLS.Conn, ConnectOptions})
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.reconnect_controller), NATS.Connection, IOBuffer, TLS.Conn, TLS.Conn, ConnectOptions})
precompile(Tuple{typeof(NATS.next_protocol_message), TLS.Conn})
precompile(Tuple{typeof(NATS.receiver), NATS.Connection, TLS.Conn})
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.receiver), NATS.Connection, TLS.Conn})
precompile(Tuple{typeof(NATS.sendloop), NATS.Connection, TLS.Conn, IOBuffer})
precompile(Tuple{typeof(NATS.spawn_task), typeof(NATS.sendloop), NATS.Connection, TLS.Conn, IOBuffer})
# Connecting to a given url.
precompile(Tuple{typeof(NATS.connect), String})
precompile(Tuple{typeof(StructTypes.constructfrom), Type{NATS.Connect}, ConnectOptions})
precompile(Tuple{typeof(StructTypes.constructfrom), StructTypes.UnorderedStruct, Type{NATS.Connect}, ConnectOptions})
precompile(Tuple{Type{NATS.Connect}, Bool, Bool, Bool, Nothing, Nothing, Nothing, Nothing, String, String, Int64, Nothing, Nothing, Nothing, Bool, Bool, Nothing})
precompile(Tuple{typeof(StructTypes.constructfrom), Type{Union{Nothing, Bool}}, Bool})
precompile(Tuple{typeof(StructTypes.constructfrom), Type{Union{Nothing, Int64}}, Int64})
# Publish, subscribe, request and drain.
precompile(Tuple{typeof(NATS.publish), NATS.Connection, String})
precompile(Tuple{typeof(NATS.publish), NATS.Connection, String, String})
precompile(Tuple{typeof(NATS.publish), NATS.Connection, String, Tuple{String, Vector{Pair{String, String}}}})
precompile(Tuple{typeof(NATS.subscribe), Function, NATS.Connection, String})
precompile(Tuple{typeof(NATS.reply), Function, NATS.Connection, String})
precompile(Tuple{typeof(NATS.next), NATS.Connection, NATS.Sub})
precompile(Tuple{typeof(NATS.payload), NATS.Msg})
precompile(Tuple{typeof(NATS.unsubscribe), NATS.Connection, NATS.Sub})
precompile(Tuple{typeof(NATS.drain), NATS.Connection, NATS.Sub})
precompile(Tuple{typeof(NATS.drain), NATS.Connection})
precompile(Tuple{typeof(NATS.request), NATS.Connection, String})
precompile(Tuple{typeof(NATS.request), NATS.Connection, String, String})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:timeout,), Tuple{Int64}}, typeof(NATS.request), NATS.Connection, String, String})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:timeout,), Tuple{Float64}}, typeof(NATS.request), NATS.Connection, String, String})

end
