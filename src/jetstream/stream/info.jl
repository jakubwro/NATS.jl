

function stream_info(connection::NATS.Connection,
                     stream_name::String;
                     no_throw = false,
                     deleted_details = false,
                     subjects_filter::Union{String, Nothing} = nothing)
    validate_name(stream_name)
    res = NATS.request(Union{StreamInfo, ApiError}, connection, "\$JS.API.STREAM.INFO.$(stream_name)")
    no_throw || res isa ApiError && throw(res)
    res
end

function iterable_request(f)
    offset = 0
    iterable = f(offset)
    offset = iterable.offset + iterable.limit
    while iterable.total > offset
        iterable = f(offset)
        offset = iterable.offset + iterable.limit
    end
end

function stream_infos(connection::NATS.Connection, subject = nothing)
    result = StreamInfo[]
    req = Dict()
    if !isnothing(subject)
        req[:subject] = subject
    end
    iterable_request() do offset
        req[:offset] = offset
        json = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.LIST", JSON3.write(req))
        throw_on_api_error(json)
        if !isnothing(json.streams)
            for s in json.streams
                item = StructTypes.constructfrom(StreamInfo, s)
                push!(result, item)
            end
        end
        StructTypes.constructfrom(IterableResponse, json)
    end
    result
end

function stream_names(connection::NATS.Connection, subject = nothing; timer = Timer(5))
    result = String[]
    offset = 0
    req = Dict()
    if !isnothing(subject)
        req[:subject] = subject
    end
    iterable_request() do offset
        req[:offset] = offset
        json = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.NAMES", JSON3.write(req); timer)
        throw_on_api_error(json)
        if !isnothing(json.streams)
            append!(result, json.streams)
        end
        StructTypes.constructfrom(IterableResponse, json)
    end
    result
end
