

struct JetDict{T}
    connection::NATS.Connection
    bucket::String
    stream_info::StreamInfo
    T::DataType
    revisions::ScopedValue{Dict{String, UInt64}}
end

function JetDict{T}(connection::NATS.Connection, bucket::String) where T
    NATS.find_msg_conversion_or_throw(T)
    NATS.find_data_conversion_or_throw(T)
    stream = streaminfo(connection, "KV_$bucket")
    if isnothing(stream)
        stream = create_or_update_kv(connection, )
    end
    JetDict{T}(connection, bucket, stream_info, T)
end

const DEFAULT_JETSTREAM_OPTIMISTIC_RETRIES = 3

function with_optimistic_concurrency(f, kv::JetDict; retry = true)
    with(kv.revisions => Dict{String, UInt64}()) do
        for _ in 1:DEFAULT_JETSTREAM_OPTIMISTIC_RETRIES
            try
                f()
            catch err
                if err isa ApiError && err.err_code == 10071
                    @warn "Key update clash."
                    retry && continue
                else
                    rethrow()
                end
            end
        end
    end
end

function history(jetdict::JetDict)::Vector{JetEntry}

end
