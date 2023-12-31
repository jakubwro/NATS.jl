### state.jl
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
# This file contains utilities for maintaining global state of NATS.jl package.
#
### Code:

function default_fallback_handler(::Connection, msg::Msg)
    # @warn "Unexpected message delivered." msg
end

@kwdef mutable struct State
    connections::Vector{Connection} = Connection[]
    "Handlers of messages for which handler was not found."
    fallback_handlers::Vector{Function} = Function[default_fallback_handler]
    lock::ReentrantLock = ReentrantLock()
    stats::Stats = Stats()
    sub_stats::Dict{String, Stats} = Dict{String, Stats}()
end

const state = State()

# Allow other packages to handle unexpected messages.
# JetStream might want to `nak` messages that need acknowledgement.
function install_fallback_handler(f)
    @lock state.lock begin
        push!(state.fallback_handlers, f)
    end
end

function connection(id::Integer)
    if id in 1:length(state.connections)
        state.connections[id]
    else
        error("Connection #$id does not exists.")
    end
end

# """
# Cleanup subscription data when no more messages are expected.
# """
function _cleanup_sub(nc::Connection, sid::String)
    @lock state.lock begin
        ch = get(nc.sub_channels, sid, nothing)
        !isnothing(ch) && close(ch)
        delete!(nc.sub_channels, sid)
    end
    @lock nc.lock begin
        delete!(nc.subs, sid)
        delete!(nc.unsubs, sid)
    end

end

# """
# Update state on message received.
# """
function _cleanup_unsub_msg(nc::Connection, sid::AbstractString, n::Int64)
    lock(nc.lock) do
        count = get(nc.unsubs, sid, nothing)
        if !isnothing(count)
            count -= n
            if count <= 0
                _cleanup_sub(nc, sid)
            else
                nc.unsubs[sid] = count
            end
        end
    end
end
