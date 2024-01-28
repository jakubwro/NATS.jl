
function check_api_call_error(s, e)
    e isa Union{NATS.NATSError, ApiError} && e.code == 503
end

const DEFAULT_API_CALL_DELAYS = ExponentialBackOff(n = typemax(Int64), first_delay = 0.2, max_delay = 0.5)

function jetstream_api_call(T, connection::NATS.Connection, subject, data = nothing; delays = DEFAULT_API_CALL_DELAYS)
    call_retry = retry(NATS.request; delays, check = check_api_call_error)
    call_retry(T, connection, subject, data)
end
