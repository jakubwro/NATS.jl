# Global state.

function default_fallback_handler(::Connection, msg::Union{Msg, HMsg})
    # @warn "Unexpected message delivered." msg
end

@kwdef mutable struct State
    default_connection::Union{Connection, Nothing} = nothing
    connections::Vector{Connection} = Connection[]
    handlers::Dict{String, Channel} = Dict{String, Function}()
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

function connection(id::Symbol)
    if id === :default
        nc = @lock state.lock state.default_connection
        isnothing(nc) && error("No default connection availabe. Call `NATS.connect(default = true)` before. See https://jakubwro.github.io/NATS.jl/dev/connect") #TODO: move docs url to consts
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
function _cleanup_unsub_msg(nc::Connection, sid::AbstractString)
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
