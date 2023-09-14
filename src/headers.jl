const Header = Pair{String, String}
const Headers = Vector{Header}

function serialize_header(::Nothing)
    ""
end

function serialize_header(headers::Vector{Pair{String, String}})
    buf = IOBuffer()
    write(buf, "NATS/1.0\r\n")
    for (key, value) in headers
        write(buf, key)
        write(buf, ": ")
        write(buf, value)
        write(buf, "\r\n")
    end
    return String(take!(buf))
end

function deserialize_header(header_str::AbstractString)
    hdr = split(header_str, "\r\n"; keepempty = false)
    @assert startswith(first(hdr), "NATS/1.0") "Missing protocol version."
    items = hdr[2:end]
    items = split.(items, ": "; keepempty = false)
    map(x -> string(first(x)) => string(last(x)) , items)
end

function header_values(h::Headers, key::String)
    last.(filter(p -> first(p) == key, h))
end


function statuscode(header_str::String)
    hdr = split(header_str, "\r\n"; keepempty = false, limit = 2)
    if ' ' in first(hdr)
        version, status = split(first(hdr), ' ')
        parse(Int, status)
    else
        200
    end
end

function statuscode(::Msg)
    200
end

function statuscode(hmsg::HMsg)
    statuscode(hmsg.headers)
end