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

@kwdef mutable struct State
    connections::Vector{Connection} = Connection[]
    lock::ReentrantLock = ReentrantLock()
    stats::Stats = Stats()
end

const state = State()

# Allow other packages to handle unexpected messages.
# JetStream might want to `nak` messages that need acknowledgement.
function install_fallback_handler(f, nc::Connection)
    @lock state.lock begin
        if !(f in nc.fallback_handlers)
            push!(nc.fallback_handlers, f)
        end
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
function _delete_sub_data(nc::Connection, sid::Int64)
    @lock nc.lock begin
        sub_data = get(nc.sub_data, sid, nothing)
        if isnothing(sub_data)
            # Already cleaned up by other task.
            return
        end
        close(sub_data.channel)
        if sub_data.is_async == true || Base.n_avail(sub_data.channel) == 0
            # `next` rely on lookup of sub data, in this case let sub data stay and do cleanup
            # when `next` gets the last message of a closed channel.
            delete!(nc.sub_data, sid)
            delete!(nc.unsubs, sid)
        end
    end
end

# """
# Update state on message received.
# """
function _update_unsub_counter(nc::Connection, sid::Int64, n::Int64)
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
