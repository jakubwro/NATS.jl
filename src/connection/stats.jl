const NATS_STATS_MAX_RECENT_ERRORS = 100
mutable struct Stats
    "Count of msgs received but maybe not yet handled by subscription."
    @atomic msgs_received::Int64
    "Count of msgs handled without error."
    @atomic msgs_handled::Int64
    "Count of msgs that caused handler function error."
    @atomic msgs_errored::Int64
    "Msgs that was not put to a subscription channel because it was full or `sid` was not known."
    @atomic msgs_dropped::Int64
    "Msgs published count."
    @atomic msgs_published::Int64
    "Subscription handlers running at the moment count."
    @atomic handlers_running::Int64
    "Recent errors."
    errors::Channel{Exception}
    function Stats()
        new(0, 0, 0, 0, 0, 0, Channel{Exception}(NATS_STATS_MAX_RECENT_ERRORS))
    end
end

function show(io::IO, stats::Stats)
     print(io, "published: $(stats.msgs_received) \n")
     print(io, " received: $(stats.msgs_received) \n")
     print(io, "   active: $(stats.handlers_running) \n")
     print(io, "  handled: $(stats.msgs_handled) \n")
     print(io, "  errored: $(stats.msgs_received) \n")
     print(io, "  dropped: $(stats.msgs_received) \n")
end


macro inc_stat(field, stats...)
    exprs = map(stats) do stat
        :($(esc(Base.modifyproperty!))($(esc(stat)), $field, $(esc(Base.:+)), 1, :sequentially_consistent))
    end
    Expr(:block, exprs...)
end

macro dec_stat(field, stats...)
    exprs = map(stats) do stat
        :($(esc(Base.modifyproperty!))($(esc(stat)), $field, $(esc(Base.:-)), 1, :sequentially_consistent))
    end
    Expr(:block, exprs...)
end