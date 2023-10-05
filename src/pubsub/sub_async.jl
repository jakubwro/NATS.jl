
# function _start_async_handler(f::Function, subject::String, channel_size::Int64, error_throttling_seconds::Float64)
#     error_ch = Channel(channel_size)
#     ch = Channel(channel_size)
#     Threads.@spawn begin
#         try
#             while true
#                 msg = take!(ch)
#                 Threads.@spawn :default try
#                     f(msg)
#                 catch err
#                     try
#                         put!(error_ch, err)
#                     catch
#                         @debug "Error channel is full for sub on $subject."
#                     end
#                 end
#             end
#         catch err
#             if err isa InvalidStateException
#                 # This is fine, subscription is unsubscribed.
#                 @debug "Task for subscription on $subject finished."
#             else
#                 @error "Unexpected error." err
#             end
#             close(error_ch)
#         end
#     end
#     Threads.@spawn :default begin
#         while true
#             sleep(error_throttling_seconds) # TODO: check diff and adjust
#             avail = Base.n_avail(error_ch)
#             errors = [ take!(error_ch) for _ in 1:avail ]
#             if !isempty(errors)
#                 @error "$(length(errors)) handler errors on \"$subject\" in last 5 s. Last one:" last(errors)
#             end
#         end
#     end
#     ch
# end
