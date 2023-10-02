
# """
# digraph G {
#   connecting   -> connected
#   connected    -> reconnecting
#   reconnecting -> connected
#   connected    -> draining
#   draining     -> drained
# }
# """
@enum ConnectionStatus CONNECTING CONNECTED RECONNECTING DRAINING DRAINED

mutable struct Stats
    msgs_handled::Int64
    msgs_not_handled::Int64
end

mutable struct Connection
    status::ConnectionStatus
    info::Channel{Info}
    outbox::Channel{ProtocolMessage}
    subs::Dict{String, Sub}
    unsubs::Dict{String, Int64}
    stats::Stats
    rng::AbstractRNG
    function Connection()
        new(CONNECTING, Channel{Info}(10), Channel{ProtocolMessage}(OUTBOX_SIZE), Dict{String, Sub}(), Dict{String, Int64}(), Stats(0, 0), MersenneTwister())
    end
end

mutable struct State
    default_connection::Union{Connection, Nothing}
    connections::Vector{Connection}
    handlers::Dict{String, Channel}
    "Handlers of messages for which handler was not found."
    fallback_handlers::Vector{Function}
    lock::ReentrantLock
    stats::Stats
end
