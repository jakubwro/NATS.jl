### parser.jl
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
# This file contains implementations of NATS protocol parsers.
#
### Code:

@enum ParserState OP_START OP_PLUS OP_PLUS_O OP_PLUS_OK OP_MINUS OP_MINUS_E OP_MINUS_ER OP_MINUS_ERR OP_MINUS_ERR_SPC MINUS_ERR_ARG OP_M OP_MS OP_MSG OP_MSG_SPC MSG_ARG MSG_PAYLOAD MSG_END OP_P OP_H OP_PI OP_PIN OP_PING OP_PO OP_PON OP_PONG OP_I OP_IN OP_INF OP_INFO OP_INFO_SPC INFO_ARG

# Parser state and temporary buffers for parsing subscription messages.
@kwdef mutable struct ParserData
    state::ParserState = OP_START
    has_header::Bool = false
    subject_range::UnitRange{Int64} = 1:0
    sid::Int64 = 0
    reply_to_range::UnitRange{Int64} = 1:0
    payload_start = 0
    header_bytes::Int64 = 0
    total_bytes::Int64 = 0
    arg_begin::Int64 = -1
    arg_no::Int64 = 0
    args::Vector{UnitRange{Int64}} = UnitRange{Int64}[0:0, 0:0, 0:0, 0:0, 0:0]
    payload_buffer::Vector{UInt8} = UInt8[]
    results::Vector{ProtocolMessage} = ProtocolMessage[]
end

function parse_error(buffer, pos, data::ParserData)
    buf = String(buffer[max(begin, pos-100):min(end,pos+100)])
    error("Parser error on position $pos: $buf\nBuffer length: $(length(buffer))")
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
        empty!(data.results)
    end
end

macro uint8(char::Char)
    convert(UInt8, char)
end


@inline function bytes_to_int64(buffer, range)::Int64
    ret = Int64(0)
    for i in range
        ret = (ret << 3) + (ret << 1)
        ret += buffer[i] - 0x30
    end
    ret
end

function parse_buffer(io::IO, buffer::Vector{UInt8}, data::ParserData)
    pos = 0
    len = length(buffer)
    while pos < len
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
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PLUS
            if byte == (@uint8 'O') || byte == (@uint8 'o')
                data.state = OP_PLUS_O
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PLUS_O
            if byte == (@uint8 'K') || byte == (@uint8 'k')
                data.state = OP_PLUS_OK
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PLUS_OK
            if byte == (@uint8 '\r')
            elseif byte == (@uint8 '\n')
                push!(data.results, Ok())
                data.state = OP_START
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MINUS 
            if byte == (@uint8 'E') || byte == (@uint8 'e')
                data.state = OP_MINUS_E
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MINUS_E
            if byte == (@uint8 'R') || byte == (@uint8 'r')
                data.state = OP_MINUS_ER
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MINUS_ER
            if byte == (@uint8 'R') || byte == (@uint8 'r')
                data.state = OP_MINUS_ERR
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MINUS_ERR
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                data.state = OP_MINUS_ERR_SPC
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MINUS_ERR_SPC
            if byte == @uint8 ' '
                data.state = OP_MINUS_ERR_SPC
            elseif byte == @uint8 '\''
                data.state = MINUS_ERR_ARG
            else
                parse_error(buffer, pos, data)
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
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MS
            if byte == (@uint8 'G') || byte == (@uint8 'g')
                data.state = OP_MSG
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MSG
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                data.state = OP_MSG_SPC
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_MSG_SPC
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                # Skip all spaces.
            else
                data.arg_begin = pos
                data.arg_no += 1
                if pos == len
                    rest = readuntil(io, "\r\n")
                    append!(buffer, rest, "\r\n")
                    len += length(rest) + 2
                end
                data.state = MSG_ARG
            end
        elseif data.state == MSG_ARG
            if pos == len && byte != (@uint8 '\n')
                rest = readuntil(io, "\r\n")
                len += length(rest) + 2
                append!(buffer, rest, "\r\n")
            end
            if byte == (@uint8 ' ') || byte == (@uint8 '\t')
                argrange = range(data.arg_begin, pos-1)
                isempty(argrange) || (data.args[data.arg_no] = argrange)
                data.arg_begin = pos+1
                isempty(argrange)  || (data.arg_no += 1)
            elseif byte == (@uint8 '\r')
                data.args[data.arg_no] =  range(data.arg_begin, (pos-1))
            elseif byte == (@uint8 '\n')
                subject_range = data.args[1]
                if data.has_header
                    if data.arg_no == 4
                        data.header_bytes = bytes_to_int64(buffer, data.args[3])
                        data.total_bytes = bytes_to_int64(buffer, data.args[4])
                        data.reply_to_range = 1:0
                    elseif data.arg_no == 5
                        data.header_bytes = bytes_to_int64(buffer, data.args[4])
                        data.total_bytes = bytes_to_int64(buffer, data.args[5])
                        data.reply_to_range = data.args[3]
                    else
                        parse_error(buffer, pos, data)
                    end
                else
                    if data.arg_no == 3
                        data.header_bytes = 0
                        data.total_bytes = bytes_to_int64(buffer, data.args[3])
                        data.reply_to_range = 1:0
                    elseif data.arg_no == 4
                        data.total_bytes = bytes_to_int64(buffer, data.args[4])
                        data.header_bytes = 0
                        data.reply_to_range = data.args[3]
                    else
                        parse_error(buffer, pos, data)
                    end
                end
                ending = pos + data.total_bytes + 2
                if ending > len
                    rest = read(io, ending - len)
                    len += length(rest)
                    append!(buffer, rest)
                end
                payload_range = range(pos+1, pos + data.total_bytes)
                pos = pos + data.total_bytes + 2
                msg = MsgRaw(data.sid, buffer, subject_range, data.reply_to_range, data.header_bytes, payload_range)
                push!(data.results, msg)
                data.arg_no = 0
                data.sid = 0
                data.state = OP_START
            else
                if data.arg_no == 2
                    data.sid = data.sid * 10
                    data.sid += byte - 0x30
                end
            end
        elseif data.state == OP_P
            if byte == (@uint8 'I') || byte == (@uint8 'i')
                data.state = OP_PI
            elseif byte == (@uint8 'O') || byte == (@uint8 'o')
                data.state = OP_PO
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_H
            if byte == (@uint8 'M') || byte == (@uint8 'm') 
                data.state = OP_M
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PI 
            if byte == (@uint8 'N') || byte == (@uint8 'n') 
                data.state = OP_PIN
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PIN
            if byte == (@uint8 'G') || byte == (@uint8 'g') 
                data.state = OP_PING
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PING
            if byte == (@uint8 '\r')
                #Do nothing
            elseif byte == (@uint8 '\n')
                push!(data.results, Ping())
                data.state = OP_START
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PO
            if byte == (@uint8 'N') || byte == (@uint8 'n') 
                data.state = OP_PON
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PON
            if byte == (@uint8 'G') || byte == (@uint8 'g') 
                data.state = OP_PONG
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_PONG
            if byte == (@uint8 '\r')
                #Do nothing
            elseif byte == (@uint8 '\n')
                push!(data.results, Pong())
                data.state = OP_START
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_I
            if byte == (@uint8 'N') || byte == (@uint8 'n') 
                data.state = OP_IN
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_IN
            if byte == (@uint8 'F') || byte == (@uint8 'f') 
                data.state = OP_INF
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_INF
            if byte == (@uint8 'O') || byte == (@uint8 'o') 
                data.state = OP_INFO
            else
                parse_error(buffer, pos, data)
            end
        elseif data.state == OP_INFO
            if byte == (@uint8 ' ') || byte == (@uint8 '\t') 
                data.state = OP_INFO_SPC
            else
                parse_error(buffer, pos, data)
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

# Simple interactive parser for protocol initialization.

function next_protocol_message(io::IO)::ProtocolMessage
    headline = readuntil(io, "\r\n")
    if     startswith(uppercase(headline), "+OK")  Ok()
    elseif startswith(uppercase(headline), "PING") Ping()
    elseif startswith(uppercase(headline), "PONG") Pong()
    elseif startswith(uppercase(headline), "-ERR") parse_err(headline)
    elseif startswith(uppercase(headline), "INFO") parse_info(headline)
    elseif startswith(uppercase(headline), "MSG")  error("Parsing MSG not supported")
    elseif startswith(uppercase(headline), "HMSG") error("Parsing HMSG not supported")
    else                                           error("Unexpected protocol message: '$headline'.")
    end
end

function parse_info(headline::String)::Info
    json = SubString(headline, ncodeunits("INFO "))
    JSON3.read(json, Info)
end

function parse_err(headline::String)::Err
    left = ncodeunits("-ERR '") + 1
    right = ncodeunits(headline) - ncodeunits("'")
    Err(headline[left:right])
end
