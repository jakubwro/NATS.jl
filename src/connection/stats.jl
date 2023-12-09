### stats.jl
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
# This file contains utilities for collecting statistics connections, subscrptions and NATS.jl package.
#
### Code:

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
     print(io, "published: $(stats.msgs_published) \n")
     print(io, " received: $(stats.msgs_received) \n")
     print(io, "   active: $(stats.handlers_running) \n")
     print(io, "  handled: $(stats.msgs_handled) \n")
     print(io, "  errored: $(stats.msgs_errored) \n")
     print(io, "  dropped: $(stats.msgs_dropped) \n")
end


macro inc_stat(field, value, stats...)
    exprs = map(stats) do stat
        :($(esc(Base.modifyproperty!))($(esc(stat)), $field, $(esc(Base.:+)), $(esc(value)), :sequentially_consistent))
    end
    Expr(:block, exprs...)
end

macro dec_stat(field, value, stats...)
    exprs = map(stats) do stat
        :($(esc(Base.modifyproperty!))($(esc(stat)), $field, $(esc(Base.:-)), $(esc(value)), :sequentially_consistent))
    end
    Expr(:block, exprs...)
end