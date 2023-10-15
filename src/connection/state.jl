# Global state.

mutable struct State
    default_connection::Union{Connection, Nothing}
    connections::Vector{Connection}
    handlers::Dict{String, Channel}
    "Handlers of messages for which handler was not found."
    fallback_handlers::Vector{Function}
    lock::ReentrantLock
    stats::Stats
    sub_stats::Dict{String, Stats}
end

function default_fallback_handler(::Connection, msg::Union{Msg, HMsg})
    @warn "Unexpected message delivered." msg
end

const state = State(nothing, Connection[], Dict{String, Function}(), Function[default_fallback_handler], ReentrantLock(), Stats(), Dict{String, Stats}())

function connection(id::Symbol)
    if id === :default
        nc = @lock state.lock state.default_connection
        isnothing(nc) && error("No default connection availabe. Call `NATS.connect(default = true)` before.")
        nc
    else
        error("Connection `:$id` does not exits.")
    end
end

function connection(id::Symbol, nc::Connection)
    if id === :default
        @lock state.lock state.default_connection = nc
    else
        error("Cannot set connection `:$id`, expected `:default`.")
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
    lock(state.lock) do
        ch = get(state.handlers, sid, nothing)
        !isnothing(ch) && close(ch)
        delete!(state.handlers, sid)
        delete!(nc.subs, sid)
        delete!(nc.unsubs, sid)
    end
end

# """
# Update state on message received.
# """
function _cleanup_unsub_msg(nc::Connection, sid::String)
    lock(state.lock) do
        count = get(nc.unsubs, sid, nothing)
        if !isnothing(count)
            count = count - 1
            if count == 0
                _cleanup_sub(nc, sid)
            else
                nc.unsubs[sid] = count
            end
        end
    end
end
