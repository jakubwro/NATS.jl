include("sub_sync.jl")
include("sub_async.jl")

"""
$(SIGNATURES)

Subscribe to a subject.
"""
function subscribe(
    f,
    subject::String;
    connection::Connection = connection(:default),
    queue_group::Union{String, Nothing} = nothing,
    async_handlers = false,
    channel_size = SUBSCRIPTION_CHANNEL_SIZE,
    error_throttling_seconds = SUBSCRIPTION_ERROR_THROTTLING_SECONDS
)
    arg_t = argtype(f)
    find_msg_conversion_or_throw(arg_t)
    f_typed = _fast_call(f, arg_t)
    sid = @lock NATS.state.lock randstring(connection.rng, 20) # TODO: make helper method
    sub = Sub(subject, queue_group, sid)
    channel = _start_tasks(f_typed, async_handlers, subject, channel_size, error_throttling_seconds)
    @lock NATS.state.lock begin
        state.handlers[sid] = channel
        connection.subs[sid] = sub
    end
    send(connection, sub)
    sub
end

function _start_tasks(f::Function, async_handlers::Bool, subject::String, channel_size::Int64, error_throttling_seconds::Float64)
    last_error = nothing
    last_error_msg = nothing
    errors_since_last_log = 0
    handlers_running = Threads.Atomic{Int64}(0)
    lock = ReentrantLock()
    ch = Channel(channel_size)

    if async_handlers == true
        Threads.@spawn begin
            try
                while true
                    msg = take!(ch)
                    handler_task = Threads.@spawn :default begin
                        Threads.atomic_add!(handlers_running, 1)
                        try
                            f(msg)
                        catch err
                            @lock lock begin
                                last_error = err
                                last_error_msg = msg
                                errors_since_last_log = errors_since_last_log + 1
                            end
                        end
                        Threads.atomic_sub!(handlers_running, 1)
                    end
                    async_handlers || wait(handler_task)
                end
            catch err
                if err isa InvalidStateException
                    # This is fine, subscription is unsubscribed.
                    @debug "Task for subscription on $subject finished."
                else
                    @error "Unexpected subscription error." err
                end
            end
        end
    else
        Threads.@spawn begin
            try
                while true
                    msg = take!(ch)
                    Threads.atomic_add!(handlers_running, 1)
                    try
                        f(msg)
                    catch err
                        @lock lock begin
                            last_error = err
                            last_error_msg = msg
                            errors_since_last_log = errors_since_last_log + 1
                        end
                    end
                    Threads.atomic_sub!(handlers_running, 1)
                end
            catch err
                if err isa InvalidStateException
                    # This is fine, subscription is unsubscribed.
                    @debug "Task for subscription on $subject finished."
                else
                    @error "Unexpected subscription error." err
                end
            end
        end
    end

    monitor_task = Threads.@spawn :default begin
        while isopen(ch)
            sleep(error_throttling_seconds) # TODO: check diff and adjust
            errs, err, msg = @lock lock begin
                errors_since_last_log_save = errors_since_last_log
                errors_since_last_log = 0
                errors_since_last_log_save, last_error, last_error_msg
            end
            if errs > 0
                @error "$errs handler errors on \"$subject\" in last 5 s." err msg
            end
        end
    end
    errormonitor(monitor_task)

    stats_task = Threads.@spawn :default begin
        while isopen(ch) || Base.n_avail(ch) > 0
            if handlers_running.value > 1000
                @warn "$(handlers_running.value) handlers running for subscription on $subject."
                last_warning = time()
            end
            level = Base.n_avail(ch) / ch.sz_max
            if level > 0.8
                @warn "Subscription on $subject channel full in $level %"
                last_warning = time()
            end
            sleep(20)
        end
    end
    errormonitor(stats_task)

    ch
end