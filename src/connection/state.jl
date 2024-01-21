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
function _delete_sub_data(nc::Connection, sid::String)
    @lock nc.lock begin
        sub_data = get(nc.sub_data, sid, nothing)
        if sub_data.is_async == true
            !isnothing(sub_data) && close(sub_data.channel)
            delete!(nc.sub_data, sid)
            delete!(nc.unsubs, sid)
        else
            # `next` rely on lookup of sub data, in this case let sub data stay and do cleanup
            # when `next` gets the last message of a closed channel.
            !isnothing(sub_data) && close(sub_data.channel)
        end
    end
end

# """
# Update state on message received.
# """
function _update_unsub_counter(nc::Connection, sid::String, n::Int64)
    lock(nc.lock) do
        count = get(nc.unsubs, sid, nothing)
        if !isnothing(count)
            count -= n
            if count <= 0
                _delete_sub_data(nc, sid)
            else
                nc.unsubs[sid] = count
            end
        end
    end
end
