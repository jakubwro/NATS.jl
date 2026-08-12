### muxer.jl
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
# This file contains the request inbox multiplexer.
#
# A naive `request` creates a subscription per request, which costs a SUB and
# an UNSUB round trip and mutates the connection wide subscription registry on
# every call. Instead a single wildcard subscription on `<prefix>.*` is created
# lazily per connection and replies are routed to per request channels by the
# last token of the reply subject.
#
# This works because a responder publishes to the `reply_to` subject it was
# given, so the reply arrives on `<prefix>.<token>`.
#
# JetStream pull consumers (`$JS.API.CONSUMER.MSG.NEXT.*`) break that
# assumption. Their replies are stored stream messages, delivered with the
# original *stream* subject, an unrelated `$JS.ACK...` reply_to and no header
# identifying the inbox. Nothing in such a reply names the request that asked
# for it, so a shared wildcard subscription cannot demultiplex them. Those
# requests fall back to a dedicated subscription, which is what nats.go does
# for pull consumers as well. `request_dedicated_inbox` selects that path.
#
### Code:

# """
# Lazily create the wildcard subscription that receives replies for all
# muxed requests issued on this connection.
# """
function start_muxer!(nc::Connection)
    # Fast path, the muxer is created once and then reused.
    existing = @lock nc.reply_lock nc.reply_subject
    isnothing(existing) || return existing

    # `muxer_init_lock` is held across `subscribe` so that a second task cannot
    # observe the prefix and publish a request before the SUB has been sent,
    # which would lose the reply. It is a distinct lock from `reply_lock` so
    # that reply routing is never blocked behind subscription setup, and it is
    # only ever taken before `nc.lock`, never while holding it.
    @lock nc.muxer_init_lock begin
        existing = @lock nc.reply_lock nc.reply_subject
        isnothing(existing) || return existing

        prefix = "$(nc.inbox_prefix)$(randstring(nc.rng, INBOX_RANDOM_LENGTH))"
        sub = subscribe(nc, "$prefix.*") do msg
            deliver_reply(nc, msg)
        end
        @lock nc.reply_lock begin
            nc.reply_sub = sub
            nc.reply_subject = prefix
        end
        prefix
    end
end

# """
# Route a reply to the channel of the request that is waiting for it.
# """
function deliver_reply(nc::Connection, msg::Msg)
    token = reply_token(msg.subject)
    ch = @lock nc.reply_lock get(nc.reply_channels, token, nothing)
    if isnothing(ch)
        # The requester already collected everything it wanted, or timed out.
        inc_stats(:msgs_dropped, 1, state.stats, nc.stats)
        return
    end
    try
        # Never block the muxer task. The channel is sized to the number of
        # replies asked for, so a service that sends more than that gets the
        # surplus dropped rather than stalling every other in flight request.
        if Base.n_avail(ch) >= ch.sz_max
            inc_stats(:msgs_dropped, 1, state.stats, nc.stats)
            return
        end
        put!(ch, msg)
    catch err
        # Channel closed concurrently by a timeout or by the requester.
        err isa InvalidStateException || rethrow()
    end
    nothing
end

# Last dot separated token of a reply subject, which identifies the request.
function reply_token(subject::AbstractString)
    idx = findlast('.', subject)
    isnothing(idx) ? subject : SubString(subject, idx + 1)
end

# """
# Tell whether replies to `subject` can be demultiplexed by the shared inbox
# subscription. JetStream pull consumer replies carry the stream subject rather
# than the inbox, so they need a dedicated subscription.
# """
function request_dedicated_inbox(subject::AbstractString)
    contains(subject, "\$JS.API.CONSUMER.MSG.NEXT.")
end

# """
# Register a channel to collect up to `nreplies` replies. Returns the subject
# to put in the `reply_to` field, a token to release the registration with, and
# the channel to read replies from.
# """
function register_reply_channel(nc::Connection, nreplies::Integer)
    prefix = start_muxer!(nc)
    ch = Channel{Msg}(nreplies)
    token = @lock nc.reply_lock begin
        # Retry on the astronomically unlikely token collision rather than
        # silently cross wiring two in flight requests.
        token = randstring(nc.rng, INBOX_RANDOM_LENGTH)
        while haskey(nc.reply_channels, token)
            token = randstring(nc.rng, INBOX_RANDOM_LENGTH)
        end
        nc.reply_channels[token] = ch
        token
    end
    "$prefix.$token", token, ch
end

function unregister_reply_channel(nc::Connection, token::AbstractString)
    ch = @lock nc.reply_lock pop!(nc.reply_channels, token, nothing)
    isnothing(ch) || close(ch)
    nothing
end

# """
# Tear down the muxer and wake every request that is still waiting. Called on
# drain, after which the connection is no longer usable.
# """
function stop_muxer!(nc::Connection)
    channels = @lock nc.reply_lock begin
        chs = collect(values(nc.reply_channels))
        empty!(nc.reply_channels)
        nc.reply_subject = nothing
        nc.reply_sub = nothing
        chs
    end
    for ch in channels
        try close(ch) catch end
    end
    nothing
end

# """
# Tell whether `sid` belongs to the internal request muxer subscription rather
# than to a subscription created by the user.
# """
function is_muxer_sub(nc::Connection, sid::Int64)
    sub = @lock nc.reply_lock nc.reply_sub
    !isnothing(sub) && sub.sid == sid
end

# """
# Number of requests currently awaiting a reply on the shared inbox. Used by
# tests to assert the muxer does not leak registrations.
# """
function pending_requests(nc::Connection)
    @lock nc.reply_lock length(nc.reply_channels)
end
