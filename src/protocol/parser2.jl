

@enum ParserState OP_START OP_PLUS OP_PLUS_O OP_PLUS_OK OP_MINUS OP_MINUS_E OP_MINUS_ER OP_MINUS_ERR OP_MINUS_ERR_SPC MINUS_ERR_ARG OP_M OP_MS OP_MSG OP_MSG_SPC MSG_ARG MSG_PAYLOAD MSG_END OP_P OP_H OP_PI OP_PIN OP_PING OP_PO OP_PON OP_PONG OP_I OP_IN OP_INF OP_INFO OP_INFO_SPC INFO_ARG

# Parser state and temporary buffers for parsing subscription messages.
@kwdef mutable struct ParserData
    state::ParserState = OP_START
    has_header::Bool = false
    subject::String = ""
    sid::String = ""
    replyto::Union{String, Nothing} = nothing
    header_bytes::Int64 = 0
    total_bytes::Int64 = 0
    payload::AbstractVector{UInt8} = UInt8[]
    arg_buffers::Vector{Vector{UInt8}} = [UInt8[], UInt8[], UInt8[], UInt8[], UInt8[]]
    current_arg_buffer::Int64 = 0
    payload_buffer::Vector{UInt8} = UInt8[]
    results::Vector{ProtocolMessage} = ProtocolMessage[]
end

function next_arg(data::ParserData)
    # @show data.current_arg_buffer data.arg_buffers
    if data.current_arg_buffer == 0 || !isempty(data.arg_buffers[data.current_arg_buffer])
        data.current_arg_buffer += 1
    end
end

function write_arg(byte::UInt8, data::ParserData)
    push!(data.arg_buffers[data.current_arg_buffer], byte)
end

function parse_error(data::ParserData)
    error("parser error")
end

function parser_loop(f, io::IO)
    data = ParserData()
    # TODO: ensure eof does not block for TLS connection
    while !eof(io) # EOF indicates connection is closed, task will be stopped and reconnected.
        data_read_start = time()
        buffer = readavailable(io) # Sleeps when no data available.
        data_ready_time = time()
        parse_buffer(io, buffer, data)
        batch_ready_time = time()
        f(data.results)
        handler_call_time = time()
        # @info "Read time $(data_ready_time - data_read_start), parser time: $(batch_ready_time - data_ready_time), handler time: $(handler_call_time - batch_ready_time)" length(buffer) length(data.results)
        data.results = ProtocolMessage[]
    end
end

macro uint8(char::Char)
    convert(UInt8, char)
end

# TODO: handle multiple spaces
function parse_buffer(io::IO, buffer::Vector{UInt8}, data::ParserData)
    pos = 0
    len = length(buffer)
    while pos < length(buffer)
        pos += 1
        byte = buffer[pos]
        if data.state == OP_START
            if byte == (@uint8 'M') || byte == (@uint8 'm')
                data.state = OP_M
                data.has_header = false
            elseif byte == (@uint8 'H') || byte == (@uint8 'h')
                data.state = OP_H
                data.has_header = true
            elseif byte == (@uint8 'P') || byte == (@uint8 'p')
                data.state = OP_P
            elseif byte == (@uint8 '+')
                data.state = OP_PLUS
            elseif byte == (@uint8 '-')
                data.state = OP_MINUS
            elseif byte == (@uint8 'I') || byte == (@uint8 'i')
                data.state = OP_I
            else
                parse_error(data)
            end
        elseif data.state == OP_PLUS
            if byte == (@uint8 'O') || byte == (@uint8 'o')
                data.state = OP_PLUS_O
            else
                parse_error(data)
            end
        elseif data.state == OP_PLUS_O
            if byte == (@uint8 'K') || byte == (@uint8 'k')
                data.state = OP_PLUS_OK
            else
                parse_error(data)
            end
        elseif data.state == OP_PLUS_OK
            if byte == (@uint8 '\r')
            elseif byte == (@uint8 '\n')
                push!(data.results, Ok())
                data.state = OP_START
            else
                parse_error(data)
            end
        elseif data.state == OP_MINUS 
            if byte == (@uint8 'E') || byte == (@uint8 'e')
                data.state = OP_MINUS_E
            else
                parse_error(data)
            end
        elseif data.state == OP_MINUS_E
            if byte == (@uint8 'R') || byte == (@uint8 'r')
                data.state = OP_MINUS_ER
            else
                parse_error(data)
            end
        elseif data.state == OP_MINUS_ER
            if byte == (@uint8 'R') || byte == (@uint8 'r')
                data.state = OP_MINUS_ERR
            else
                parse_error(data)
            end
        elseif data.state == OP_MINUS_ERR
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                data.state = OP_MINUS_ERR_SPC
            else
                parse_error(data)
            end
        elseif data.state == OP_MINUS_ERR_SPC
            if byte == @uint8 ' '
                data.state = OP_MINUS_ERR_SPC
            elseif byte == @uint8 '\''
                data.state = MINUS_ERR_ARG
            else
                parse_error(data)
            end
        elseif data.state == MINUS_ERR_ARG
            if byte == (@uint8 '\'')
            elseif byte == (@uint8 '\r')
            elseif byte == (@uint8 '\n')
                push!(data.results, Err(String(data.payload_buffer)))
                data.state = OP_START
            else
                push!(data.payload_buffer, byte)
            end
        elseif data.state == OP_M
            if byte == (@uint8 'S') || byte == (@uint8 's')
                data.state = OP_MS
            else
                parse_error(data)
            end
        elseif data.state == OP_MS
            if byte == (@uint8 'G') || byte == (@uint8 'g')
                data.state = OP_MSG
            else
                parse_error(data)
            end
        elseif data.state == OP_MSG
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                data.state = OP_MSG_SPC
            else
                parse_error(data)
            end
        elseif data.state == OP_MSG_SPC
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                # Skip all spaces.
            else
                next_arg(data)
                write_arg(byte, data)
                data.state = MSG_ARG
            end
        elseif data.state == MSG_ARG
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                next_arg(data)
            elseif byte == (@uint8 '\r')
                # Nothing.
            elseif byte == (@uint8 '\n')
                data.subject = String(data.arg_buffers[1])
                data.sid = String(data.arg_buffers[2])
                if data.has_header
                    if data.current_arg_buffer == 4
                        data.replyto = nothing
                        data.header_bytes = parse(Int64, String(data.arg_buffers[3]))
                        data.total_bytes = parse(Int64, String(data.arg_buffers[4]))
                    elseif data.current_arg_buffer == 5
                        data.replyto = String(data.arg_buffers[3])
                        data.header_bytes = parse(Int64, String(data.arg_buffers[4]))
                        data.total_bytes = parse(Int64, String(data.arg_buffers[5]))
                    else
                        parse_error(data)
                    end
                else
                    if data.current_arg_buffer == 3
                        data.replyto = nothing
                        data.header_bytes = 0
                        data.total_bytes = parse(Int64, String(data.arg_buffers[3]))
                    elseif data.current_arg_buffer == 4
                        data.replyto = String(data.arg_buffers[3])
                        data.header_bytes = 0
                        data.total_bytes = parse(Int64, String(data.arg_buffers[4]))
                    else
                        parse_error(data)
                    end
                end
                data.current_arg_buffer = 0
                ending = pos + data.total_bytes + 2
                if ending > len
                    append!(buffer, read(io, ending - len))
                end
                data.payload = @view buffer[(pos + 1):(pos + data.total_bytes)]
                pos = pos + data.total_bytes + 1
                data.state = MSG_END
            else
                write_arg(byte, data)
            end
        elseif data.state == MSG_END
            msg = Msg(data.subject, data.sid, data.replyto, data.header_bytes, data.payload)
            push!(data.results, msg)
            data.state = OP_START
        elseif data.state == OP_P
            if byte == (@uint8 'I') || byte == (@uint8 'i')
                data.state = OP_PI
            elseif byte == (@uint8 'O') || byte == (@uint8 'o')
                data.state = OP_PO
            else
                parse_error(data)
            end
        elseif data.state == OP_H
            if byte == (@uint8 'M') || byte == (@uint8 'm') 
                data.state = OP_M
            else
                parse_error(data)
            end
        elseif data.state == OP_PI 
            if byte == (@uint8 'N') || byte == (@uint8 'n') 
                data.state = OP_PIN
            else
                parse_error(data)
            end
        elseif data.state == OP_PIN
            if byte == (@uint8 'G') || byte == (@uint8 'g') 
                data.state = OP_PING
            else
                parse_error(data)
            end
        elseif data.state == OP_PING
            if byte == (@uint8 '\r')
                #Do nothing
            elseif byte == (@uint8 '\n')
                push!(data.results, Ping())
                data.state = OP_START
            else
                parse_error(data)
            end
        elseif data.state == OP_PO
            if byte == (@uint8 'N') || byte == (@uint8 'n') 
                data.state = OP_PON
            else
                parse_error(data)
            end
        elseif data.state == OP_PON
            if byte == (@uint8 'G') || byte == (@uint8 'g') 
                data.state = OP_PONG
            else
                parse_error(data)
            end
        elseif data.state == OP_PONG
            if byte == (@uint8 '\r')
                #Do nothing
            elseif byte == (@uint8 '\n')
                push!(data.results, Pong())
                data.state = OP_START
            else
                parse_error(data)
            end
        elseif data.state == OP_I
            if byte == (@uint8 'N') || byte == (@uint8 'n') 
                data.state = OP_IN
            else
                parse_error(data)
            end
        elseif data.state == OP_IN
            if byte == (@uint8 'F') || byte == (@uint8 'f') 
                data.state = OP_INF
            else
                parse_error(data)
            end
        elseif data.state == OP_INF
            if byte == (@uint8 'O') || byte == (@uint8 'o') 
                data.state = OP_INFO
            else
                parse_error(data)
            end
        elseif data.state == OP_INFO
            if byte == (@uint8 ' ') || byte == (@uint8 '\t') 
                data.state = OP_INFO_SPC
            else
                parse_error(data)
            end
        elseif data.state == OP_INFO_SPC
            if byte == (@uint8 ' ') || byte == (@uint8 '\t') 
                # skip
            else
                push!(data.payload_buffer, byte)
                data.state = INFO_ARG
            end
        elseif data.state == INFO_ARG
            if byte == (@uint8 '\r')
            elseif byte == (@uint8 '\n')
                push!(data.results, JSON3.read(data.payload_buffer, Info))
                empty!(data.payload_buffer)
                data.state = OP_START
            else
                push!(data.payload_buffer, byte)
            end
        end
    end
end
