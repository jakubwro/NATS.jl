function _start_handler(f::Function, subject::String, channel_size::Int64, error_throttling_seconds::Float64)
    ch = Channel(channel_size)
    Threads.@spawn begin 
        last_error_time = time()
        errors_since_last_log = 0
        last_error = nothing
        while true
            try
                msg = take!(ch)
                f(msg)
            catch err
                if err isa InvalidStateException
                    break
                end
                last_error = err
                errors_since_last_log = errors_since_last_log + 1
                now = time()
                time_diff = now - last_error_time
                if last_error_time < now - error_throttling_seconds
                    last_error_time = now
                    @error "$errors_since_last_log handler errors on \"$subject\" in last $(round(time_diff, digits = 2)) s. Last one:" err
                    errors_since_last_log = 0
                end
            end
        end
        if errors_since_last_log > 0
            @error "$errors_since_last_log handler errors on \"$subject\"in last $(round(time() - last_error_time, digits = 2)) s. Last one:" last_error
        end
    end
    ch
end
