### subscribe.jl
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
# This file contains implementation of functions for subscribing to subjects.
#
### Code:

"""
$(SIGNATURES)

Subscribe to a subject.

Optional keyword arguments are:
- `queue_group`: NATS server will distribute messages across queue group members
- `spawn`: if `true` task will be spawn for each `f` invocation, otherwise messages are processed sequentially, default is `false`
- `channel_size`: maximum items buffered for processing, if full messages will be ignored, default is `$DEFAULT_SUBSCRIPTION_CHANNEL_SIZE`, can be configured globally with `NATS_SUBSCRIPTION_CHANNEL_SIZE` env variable
- `monitoring_throttle_seconds`: time intervals in seconds that handler errors will be reported in logs, default is `$DEFAULT_SUBSCRIPTION_ERROR_THROTTLING_SECONDS` seconds, can be configured globally with `NATS_SUBSCRIPTION_ERROR_THROTTLING_SECONDS` env variable
"""
function subscribe(
    f,
    connection::Connection,
    subject::String;
    queue_group::Union{String, Nothing} = nothing,
    spawn::Bool = false,
    channel_size::Int64 = parse(Int64, get(ENV, "NATS_SUBSCRIPTION_CHANNEL_SIZE", string(DEFAULT_SUBSCRIPTION_CHANNEL_SIZE))),
    monitoring_throttle_seconds::Float64 = parse(Float64, get(ENV, "NATS_SUBSCRIPTION_ERROR_THROTTLING_SECONDS", string(DEFAULT_SUBSCRIPTION_ERROR_THROTTLING_SECONDS)))
)
    f_typed = _fast_call(f)
    sid = new_sid(connection)
    sub = Sub(subject, queue_group, sid)
    sub_stats = Stats()
    subscription_channel = Channel(channel_size)
    with(scoped_subscription_stats => sub_stats) do
        _start_tasks(f_typed, sub_stats, connection.stats, spawn, subject, subscription_channel, monitoring_throttle_seconds)
    end
    @lock connection.lock begin
        connection.sub_data[sid] = SubscriptionData(sub, subscription_channel, sub_stats, true, ReentrantLock())
    end
    send(connection, sub)
    sub
end

function subscribe(
    connection::Connection,
    subject::String;
    queue_group::Union{String, Nothing} = nothing,
    spawn::Bool = false,
    channel_size::Int64 = parse(Int64, get(ENV, "NATS_SUBSCRIPTION_CHANNEL_SIZE", string(DEFAULT_SUBSCRIPTION_CHANNEL_SIZE))),
)
    sid = new_sid(connection)
    sub = Sub(subject, queue_group, sid)
    sub_stats = Stats()
    subscription_channel = Channel(channel_size)
    @lock connection.lock begin
        connection.sub_data[sid] = SubscriptionData(sub, subscription_channel, sub_stats, false, ReentrantLock())
    end
    send(connection, sub)
    sub
end

function next(connection, sub; no_wait = false, no_throw = false)
    sub_data = @lock connection.lock get(connection.sub_data, sub.sid, nothing)
    if isnothing(sub_data)
        no_throw && return nothing
        throw(NATSError(499, "Client unsubscribed."))
    end
    sub_data.is_async && error("`next` is available only for synchronous subscriptions")
    ch = sub_data.channel
    if no_wait && Base.n_avail(ch) == 0
        if !isopen(ch)
            @lock connection.lock begin
                delete!(connection.sub_data, sub.sid)
                delete!(connection.unsubs, sub.sid)
            end
        end
        return nothing
    end
    msg = 
        try
            @lock sub_data.lock begin
                batch = fetch(ch)
                result = popfirst!(batch)
                isempty(batch) && take!(ch)
                result
            end
        catch err
            no_throw && return nothing
            if err isa InvalidStateException
                throw(NATSError(499, "Client unsubscribed."))
            end
            rethrow()
        finally
            if !isopen(ch) && Base.n_avail(ch) == 0
                @lock connection.lock begin
                    delete!(connection.sub_data, sub.sid)
                    delete!(connection.unsubs, sub.sid)
                end
            end
        end
    inc_stats(:msgs_handled, 1, sub_data.stats, connection.stats, state.stats)
    if !no_throw
        status = statuscode(msg)
        if status > 399
            throw(NATSError(status, "")) # TODO: extract error message
        end
    end
    msg
end

@kwdef mutable struct SubscriptionMonitoringData
    last_error::Union{Any, Nothing} = nothing
    last_error_msg::Union{Msg, Nothing} = nothing
    errors_since_last_report::Int64 = 0
    lock::ReentrantLock = Threads.ReentrantLock()
end

function report_error!(data::SubscriptionMonitoringData, err, msg::Msg)
    @lock data.lock begin
        data.last_error = err
        data.last_error_msg = msg
        data.errors_since_last_report += 1
    end
end

# Resets errors counter and obtains current state.
function reset_counter!(data::SubscriptionMonitoringData)
    @lock data.lock begin
        save = data.errors_since_last_report
        data.errors_since_last_report = 0
        save, data.last_error, data.last_error_msg
    end
end

function _start_tasks(f::Function, sub_stats::Stats, conn_stats::Stats, spawn::Bool, subject::String, subscription_channel::Channel, monitoring_throttle_seconds::Float64)
    monitoring_data = SubscriptionMonitoringData()
    if spawn == true
        subscription_task = Threads.@spawn :interactive disable_sigint() do
            try
                while true
                    msgs = take!(subscription_channel)
                    for msg in msgs
                        handler_task = Threads.@spawn :default disable_sigint() do
                            try
                                dec_stats(:msgs_pending, 1, sub_stats, conn_stats, state.stats)
                                inc_stats(:handlers_running, 1, sub_stats, conn_stats, state.stats)
                                f(msg)
                                inc_stats(:msgs_handled, 1, sub_stats, conn_stats, state.stats)
                                dec_stats(:handlers_running, 1, sub_stats, conn_stats, state.stats)
                            catch err
                                inc_stats(:msgs_errored, 1, sub_stats, conn_stats, state.stats)
                                dec_stats(:handlers_running, 1, sub_stats, conn_stats, state.stats)
                                report_error!(monitoring_data, err, msg)
                            end
                        end
                        # errormonitor(handler_task) # TODO: enable this on debug.
                    end
                end
            catch err
                err isa InvalidStateException || rethrow()
            end
        end
        errormonitor(subscription_task)
    else
        subscription_task = Threads.@spawn :default disable_sigint() do
            try
                while true
                    msgs = take!(subscription_channel)
                    for msg in msgs
                        try
                            dec_stats(:msgs_pending, 1, sub_stats, conn_stats, state.stats)
                            inc_stats(:handlers_running, 1, sub_stats, conn_stats, state.stats)
                            f(msg)
                            inc_stats(:msgs_handled, 1, sub_stats, conn_stats, state.stats)
                            dec_stats(:handlers_running, 1, sub_stats, conn_stats, state.stats)
                        catch err
                            inc_stats(:msgs_errored, 1, sub_stats, conn_stats, state.stats)
                            dec_stats(:handlers_running, 1, sub_stats, conn_stats, state.stats)
                            report_error!(monitoring_data, err, msg)
                        end
                    end
                end
            catch err
                err isa InvalidStateException || rethrow()
            end
        end
        errormonitor(subscription_task)
    end

    subscription_monitoring_task = Threads.@spawn :interactive begin
        while isopen(subscription_channel) || Base.n_avail(subscription_channel) > 0
            sleep(monitoring_throttle_seconds)
            # Warn about too many handlers running.
            handlers_running = sub_stats.handlers_running
            if handlers_running > 1000 # TODO: add to config.
                @warn "$(handlers_running) handlers running for subscription on $subject."
            end
            # Warn if subscription channel is too small.
            level = Base.n_avail(subscription_channel) / subscription_channel.sz_max
            if level > 0.8 # TODO: add to config.
                @warn "Subscription on $subject channel full in $(100 * level) %"
            end
            # Report errors thrown by the handler function.
            errs, err, msg = reset_counter!(monitoring_data)
            if errs > 0
                @error "$errs handler errors on \"$subject\" in last $monitoring_throttle_seconds s." err msg
            end

        end
        # @debug "Subscription monitoring task finished" subject
    end
    errormonitor(subscription_monitoring_task)

    nothing
end