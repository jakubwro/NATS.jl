

function argtype(handler)
    signature = first(methods(handler)).sig # TODO: handle multi methods.
    if length(signature.parameters) == 1
        Nothing
    elseif length(signature.parameters) == 2
        signature.parameters[2]
    else
        Tuple{signature.parameters[2:end]...}
    end
end

function find_msg_conversion_or_throw(T::Type)
    if T != Any && !hasmethod(Base.convert, (Type{T}, Msg))
        throw(MethodError(Base.convert, (T, Msg)))
    end
end

function find_data_conversion_or_throw(T::Type)
    if T != Any && !hasmethod(Base.show, (IO, NATS.MIME_PAYLOAD, T))
        throw(MethodError(Base.show, (IO, NATS.MIME_PAYLOAD, T)))
    end
end

# """
# Return lambda that avoids type conversions for certain types.
# Also allows for use of parameterless handlers for subs that do not need look into msg payload. 
# """
function _fast_call(f::Function, arg_t::Type)
    if arg_t === Any || arg_t === NATS.Message || arg_t == NATS.Msg || arg_t == NATS.HMsg
        f
    elseif arg_t == Nothing
        _ -> f()
    else
        msg -> f(convert(arg_t, msg))
    end
end

# """
# Alternative for `@kwdef` that works better for NATS case. 
# """
function from_kwargs(T::Type, defaults, kwargs)
    # TODO: instead of this write a macro that attaches struct fields as kwargs of a function.
    args = merge(defaults, kwargs)
    fields = fieldnames(T)
    missing_args = setdiff(fields, keys(args))
    if !isempty(missing_args)
        error("Missing keyword arguments: $missing_args.")
    end
    unknown_args = setdiff(keys(args), fields)
    if !isempty(unknown_args)
        error("Unknown keyword arguments: $unknown_args.")
    end
    args = args[fields]
    field_types = fieldtypes(T)
    for ((key, val), t) in zip(pairs(args), field_types)
        if !(val isa t)
            error("Keyword argument `$key` expected to be `$t` but `$val` of type `$(typeof(val))` encountered.")
        end
    end
    T(args...)
end

function spawn_sticky_task(f)
    t = Threads.Task(f)
    # Setting sticky flag to false makes processing 10x slower when running with multiple threads.
    t.sticky = true
    Base.Threads._spawn_set_thrpool(t, :default)
    Base.Threads.schedule(t)
    errormonitor(t)
    t
end