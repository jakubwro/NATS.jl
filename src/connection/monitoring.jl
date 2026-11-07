### monitoring.jl
#
# Copyright (C) 2026 Jakub Wronowski.
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
# This file contains the task that watches subscriptions of a connection and reports their problems in logs.
#
### Code:

# One task per connection, it ends when the connection is drained. It reads only the `Stats` of the subscriptions.
function monitor_subscriptions(nc::Connection, options::ConnectOptions)
    while status(nc) != DRAINED
        sleep(options.monitoring_throttle_seconds)
        started = time_ns()
        subs = @lock nc.lock collect(values(nc.sub_data))
        for sub_data in subs
            report_subscription(sub_data, options)
        end
        @debug "Monitored $(length(subs)) subscriptions in $(round((time_ns() - started) / 1e6; digits = 3)) ms."
    end
end

function report_subscription(sub_data::SubscriptionData, options::ConnectOptions)
    subject = sub_data.sub.subject
    stats = sub_data.stats

    # Warn about too many handlers running.
    handlers_running = @atomic stats.handlers_running
    if handlers_running > options.monitoring_handlers_limit
        @warn "$(handlers_running) handlers running for subscription on $subject."
    end

    # Warn if the subscription channel is too small. This is counted the same way as `process` does it when it drops
    # messages, in messages not in the items of the channel, as those are batches of messages.
    level = (@atomic stats.msgs_pending) / sub_data.channel.sz_max
    if level > options.monitoring_channel_level
        @warn "Subscription on $subject channel is full in $(100 * level) %, dropped messages: $(@atomic stats.msgs_dropped)"
    end

    report_handler_errors(subject, stats)
end

# Reports errors thrown by the handler function since the last report. A subscription calls it also when it ends,
# because the monitoring does not find subscriptions that are gone.
function report_handler_errors(subject::String, stats::Stats)
    errors = @atomicswap stats.errors_unreported = 0
    if errors > 0
        err, msg = @atomic stats.last_error
        @error "$errors handler errors on \"$subject\"." err msg
    end
end
