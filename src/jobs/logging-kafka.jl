struct _KafkaLogging <: _JobLoggingAPIVersion end

function JobLogMessage(::_KafkaLogging, json::Dict)
    offset = _get_json(json, "offset", Int)
    # The timestamps in Kafka logs are in milliseconds
    value = _get_json(json, "value", Dict)
    timestamp = _ms_utc2localtz(_get_json(value, "timestamp", Int))
    message = _get_json(value, "message", String)
    metadata = _get_json_or(value, "metadata", Dict, Dict{String, Any}())
    keywords = _get_json_or(value, "keywords", Dict, Dict{String, Any}())
    stream = _get_json_or(value, "stream", String, nothing)
    JobLogMessage(;
        _offset=offset, timestamp, message, _metadata=metadata, _keywords=keywords,
        _legacy_eventId=nothing, _kafka_stream=stream, _json=json,
    )
end

const _KAFKA_DEFAULT_GET_TIMEOUT = 2000 # ms
const _KAFKA_DEFAULT_POLL_TIMEOUT = 10_000 # ms
mutable struct KafkaLogsBuffer <: AbstractJobLogsBuffer
    _jobname::String
    _logs::Vector{JobLogMessage}
    _found_last::Bool
    _active_range::UnitRange{Int}
    _consumer_id::Int
    _update_callback::Union{Base.Callable, Nothing}
    _stream::Union{_JobLogTask, Nothing}
    request_size_hint::Int
    _lock::ReentrantLock

    function KafkaLogsBuffer(
        f::Base.Callable,
        auth::Authentication;
        jobname::AbstractString,
        offset::Union{Integer, Nothing},
        stream::Bool,
    )
        if !isnothing(offset) && (offset < 0)
            throw(ArgumentError("Invalid `offset` value: $offset"))
        end
        # Fetch some logs, which will seed the buffer, even though we don't show any
        # logs to the user yet.
        consumer_id, logs, job_is_done = _get_logs_kafka_parsed(
            auth, jobname; offset=offset, timeout=_KAFKA_DEFAULT_GET_TIMEOUT
        )
        # The starting cursor will be an empty set of logs just at the end of any that we found,
        # so the range is (N+1):N. Essentially, the "first" log is the first non-fetched message
        # after the last one, but the "negative length" of the cursor means that the set is empty.
        # If we legitimately did not find any logs at all, then we assume that the job has not
        # generated any logs yet, and so set the active index range to 1:0, i.e. starting from
        # the very first log message.
        active_range = if isnothing(offset)
            (length(logs) + 1):length(logs)
        elseif isempty(logs) && (offset > 0)
            # If offset was specified to be >= 0 and _get_logs_kafka_parsed returned no logs
            # it _likely_ means that we're trying to fetch logs that don't exist yet.
            throw(InvalidRequestError("offset=$offset is too great, not enough logs."))
        else
            if !isempty(logs) && first(logs)._offset != offset
                @error "Bad offset returned" first(logs)._offset offset
            end
            1:0
        end
        b = new(
            jobname,
            logs,
            job_is_done,
            active_range,
            consumer_id,
            f,
            nothing,
            0,
            ReentrantLock()
        )
        # If the user requested streaming too, then we start the background task.
        stream && _job_logs_kafka_start_streaming!(auth, b)
        return b
    end
end

function Base.show(io::IO, ::MIME"text/plain", b::KafkaLogsBuffer)
    printstyled(io, "KafkaLogsBuffer"; bold=true)
    println(
        io, ": ", b._jobname, " (", length(b._active_range), " logs",
        isnothing(b._stream) ? "" : "; streaming",
        ")",
    )
    buffered_total = length(b._logs)
    buffered_start = b._active_range.start - 1
    buffered_stop = length(b._logs) - b._active_range.stop
    isfinished = b._found_last ? " (last log found)" : ""
    println(
        io,
        " buffer: Σ$buffered_total / -$(buffered_start) / +$(buffered_stop) $(isfinished)",
    )
    _print_log_list(io, b.logs; nlines=_default_display_lines(io; adjust=6))
end

# Forward lock() / unlock() to the buffer object.
Base.lock(b::KafkaLogsBuffer) = lock(b._lock)
Base.unlock(b::KafkaLogsBuffer) = unlock(b._lock)
function Base.lock(f, b::KafkaLogsBuffer)
    lock(b)
    try
        return f()
    finally
        unlock(b)
    end
end

_job_logs_active_logs(b::KafkaLogsBuffer) = b._logs[b._active_range]
_job_logs_active_logs_view(b::KafkaLogsBuffer) = @view(b._logs[b._active_range])

_kafka_next_offset(b::KafkaLogsBuffer) = isempty(b._logs) ? 0 : (last(b._logs)._offset + 1)

function _job_logs_newer!(
    auth::Authentication, b::KafkaLogsBuffer; count::Union{Integer, Nothing}=nothing
)
    # If there is a streaming task running, then this will be a no-op
    isnothing(b._stream) || return nothing
    # Check if we maybe already have `count` logs hidden away in the buffer. If we do,
    # then we just update the active log range without actually doing a request.
    if !isnothing(count) && b._active_range.stop + count <= length(b._logs)
        b._active_range = (b._active_range.start):(b._active_range.stop + count)
        _job_logs_kafka_notify_cb(b)
        return nothing
    end
    # If more logs are being requested than we have in the buffer, but we know that the
    # job has already finished and that there should not be any more messages, we will
    # also just update the active log range and return without doing another request.
    if b._found_last
        # But we only notify the user about "new logs" if we actually update the active range.
        if b._active_range.stop < length(b._logs)
            b._active_range = (b._active_range.start):length(b._logs)
            _job_logs_kafka_notify_cb(b)
        end
        return nothing
    end
    # Get the first batch of logs, starting from offset
    jobname = b._jobname
    consumer_id, logs, job_is_done = _get_logs_kafka_parsed(
        auth, jobname;
        offset=_kafka_next_offset(b),
        timeout=_KAFKA_DEFAULT_GET_TIMEOUT
    )
    job_is_done && (b._found_last = true)
    # If the returned list of logs is empty, we check if we can still update the cursor
    # maybe before returning.
    if isempty(logs) && (b._active_range.stop < length(b._logs))
        @assert b._active_range.stop + count > length(b._logs)
        b._active_range = (b._active_range.start):length(b._logs)
        _job_logs_kafka_notify_cb(b)
        return nothing
    end
    # For some reason, if offset is way beyond the last offset, the endpoint interprets it basically
    # as `offset=0`. So we return right away. TODO
    if !isempty(logs) && first(logs)._offset < _kafka_next_offset(b)
        @warn "Invalid set of logs returned." first(logs)._offset last(logs)._offset count
        error("Invalid set of logs returned")
    end
    while !isempty(logs)
        _job_logs_kafka_append_logs!(b, logs, count)
        # If we have fetched more logs than necessary, we can stop and return. Otherwise, we reduce
        # count by the number of fetched logs and carry on.
        if !isnothing(count)
            count -= length(logs)
            count <= 0 && break
        end
        # If the last batch actually finished with the end meta message, we stop not and not do any
        # more requests.
        job_is_done && break
        # Note: the consumer_id value that comes back from the backend should be the same
        # one we give in the request. But in case it is not, we'll use the new one that was
        # returned.
        next_offset = last(logs)._offset + 1
        consumer_id, logs, job_is_done = _get_logs_kafka_parsed(
            auth, jobname; offset=next_offset, consumer_id,
            timeout=_KAFKA_DEFAULT_GET_TIMEOUT
        )
        job_is_done && (b._found_last = true)
    end
    return nothing
end

# Returns the offset of the first buffered log message. If we do not have any messages buffered,
# we assume that we the buffer cursor was set up when the job hadn't produced any logs yet and
# so we are at the beginning of the log stream.
_kafka_first_offset(b::KafkaLogsBuffer) = isempty(b._logs) ? 0 : first(b._logs)._offset

function _kafka_update_active_range!(b::KafkaLogsBuffer; start=nothing, stop=nothing)
    notify_user = false
    updated_start = if isnothing(start) || b._active_range.start == start
        b._active_range.start
    else
        notify_user = true
        start
    end
    updated_stop = if isnothing(stop) || b._active_range.stop == stop
        b._active_range.stop
    else
        notify_user = true
        stop
    end
    if notify_user
        b._active_range = updated_start:updated_stop
        _job_logs_kafka_notify_cb(b)
    end
    return nothing
end

function _job_logs_older!(
    auth::Authentication, b::KafkaLogsBuffer; count::Union{Integer, Nothing}=nothing
)
    @assert isnothing(count) || count > 0
    first_offset = _kafka_first_offset(b)
    # If the buffer already starts from the first log message, then requesting additional
    # older messages is always a no-op. But we may have to update the active range.
    if first_offset == 0
        if b._active_range.start > 1
            _kafka_update_active_range!(
                b; start=isnothing(count) ? 1 : max(b._active_range.start - count, 1)
            )
        end
        return nothing
    end
    # The second option is that we haven't buffered everything, but we have enough messages
    # in the buffer to just update the active range.
    if !isnothing(count) && b._active_range.start - count > 0
        _kafka_update_active_range!(b; start=b._active_range.start - count)
        return nothing
    end
    # If we made it this far, then we know that we need to fetch additional logs. We just need to figure
    # out where to start from.
    next_offset = if isnothing(count)
        0
    else
        # We can figure out the exact offset we should start from. But, just to be a little bit greedy,
        # if we happen to know that we can anyway fetch a few more messages without doing another request
        # (based on the value of b.request_size_hint), we will, and put more of them into the buffer.
        target_offset = first_offset + b._active_range.start - count - 1
        greedy_offset = first_offset - b.request_size_hint
        # Note that it is possible that count will take us beyond the first log message
        # (offset = 0), hence the max().
        max(min(target_offset, greedy_offset), 0)
    end
    # Now that we know the starting offset, we start requesting logs until we end up at
    # first_offset. Note: because we can't request logs in the reverse direction, we need to
    # fetch _all_ the logs before we update the user.
    #
    # TODO: one option would be to put "pending" log messages into the buffer. If we support these
    # "meta" messages, we should also have "erroneous" messages for the ones that we are failing
    # to parse, to handle that case a bit more correctly and gracefully.
    #
    # Note: going in reverse, we should never encounter job stop messages, so we'll ignore those.
    jobname = b._jobname
    consumer_id, logs, _ = _get_logs_kafka_parsed(
        auth, jobname;
        offset=next_offset,
        timeout=_KAFKA_DEFAULT_GET_TIMEOUT
    )
    # This should not normally happen because we should only be asking for logs that are actually present.
    # But sometimes it does.. maybe when the timeout is not long enough? So we handle this by gracefully
    # aborting the fetch.
    if isempty(logs)
        @warn "JuliaHub returned no older logs" buffer = b jobname next_offset
        return nothing
    end
    all_logs = JobLogMessage[]
    while last(logs)._offset < (first_offset - 1)
        # If the last request gave us logs that went beyond what we need (i.e. beyond first_offset),
        # then we abort the loop. Otherwise, we push them all, and do another request, starting from
        # where we left off.
        append!(all_logs, logs)
        # Note: the consumer_id value that comes back from the backend should be the same
        # one we give in the request. But in case it is not, we'll use the new one that was
        # returned.
        next_offset = last(logs)._offset + 1
        consumer_id, logs, _ = _get_logs_kafka_parsed(
            auth, jobname; offset=next_offset, consumer_id,
            timeout=_KAFKA_DEFAULT_GET_TIMEOUT
        )
        @assert !isempty(logs)
    end
    # If the last request gave us logs that went beyond what we need (i.e. beyond first_offset),
    # then we push a subset of them and break.
    idx = findfirst(log -> (log._offset >= first_offset - 1), logs)
    append!(all_logs, @view(logs[1:idx]))
    # Actually prepend the logs to the buffer now.
    _job_logs_kafka_prepend_logs!(b, all_logs, count)
    return nothing
end

function _job_logs_kafka_start_streaming!(auth::Authentication, b::KafkaLogsBuffer)
    if !isnothing(b._stream)
        @warn "Logs are already being streamed" b._jobname
        return nothing
    end
    # If we're not already streaming, we construct a new _JobLogTask
    interrupt_channel = Channel{Nothing}(1)
    # We don't want to lock the whole buffer for the whole streaming period, because we still want
    # to be able to prepend when the streaming is going on. Instead, we lock:
    #
    # 1. When we set the ._stream field. Note that this outer lock finishes quickly, since it just sets
    #    sets up an async task, but doesn't execute it itself. If there are any newer!/older! requests
    #    still happening, we will wait for those to finish. Once ._stream has been set, the newer! requests
    #    are not allowed, so we don't have to worry about those.
    # 2. When appending new logs in the async task. This is because this might clash with an older! call
    #    We can safely keep the buffer unlocked when the long poll is happening, but we want to make sure
    #    that our append!-s and other updated don't clash with the prepend!-s from older!. We don't have
    #    worry about the offset of the last message being updated, since that can only be updated by a
    #    newer! call, which is not allowed. So it is fine that _job_logs_kafka_async does its own bookkeeping
    #    for next_offset.
    # 3. When the streaming finishes and we set ._stream = nothing. This might not really be necessary,
    #    since that assignment is probably atomic..
    lock(b) do
        t = @async begin
            jobname = b._jobname
            next_offset = isempty(b._logs) ? 0 : (last(b._logs)._offset + 1)
            @debug "KafkaLogsBuffer@async($jobname): async task started" _taskstamp()
            _job_logs_kafka_async(
                auth; jobname, next_offset, interrupt_channel
            ) do logs, job_is_done
                lock(b) do
                    _job_logs_kafka_append_logs!(b, logs)
                    job_is_done && (b._found_last = job_is_done)
                end
            end
            # Get rid of the reference to the currently running task.
            lock(b) do
                b._stream = nothing
            end
            @debug "KafkaLogsBuffer@async($jobname): async task finished" _taskstamp()
        end
        b._stream = _JobLogTask(t, interrupt_channel)
    end
    return nothing
end

function _job_logs_kafka_notify_cb(b::KafkaLogsBuffer)
    try
        b._update_callback(b, @view(b._logs[b._active_range]))
    catch e
        @error "job_logs_buffered: calling user callback errored" exception = (e, catch_backtrace())
    end
    return nothing
end

function _job_logs_kafka_append_logs!(
    b::KafkaLogsBuffer, logs, count::Union{Integer, Nothing}=nothing
)
    @assert !isempty(logs)
    if !isempty(b._logs) && last(b._logs)._offset + 1 != first(logs)._offset
        @error "Log offset mismatch!" !isempty(b._logs) && last(b._logs)._offset first(logs)._offset
    end
    append!(b._logs, logs)
    updated_stop = min(b._active_range.stop + count, length(b._logs))
    _kafka_update_active_range!(b; stop=updated_stop)
end

function _job_logs_kafka_prepend_logs!(
    b::KafkaLogsBuffer, logs, count::Union{Integer, Nothing}=nothing
)
    @assert !isempty(logs)
    @debug "_job_logs_kafka_prepend_logs!" count first(logs)._offset last(logs)._offset _kafka_first_offset(
        b
    ) typeof(logs)
    @assert last(logs)._offset < _kafka_first_offset(b)
    @assert last(logs)._offset == _kafka_first_offset(b) - 1
    prepend!(b._logs, logs)
    start_shifted = b._active_range.start + length(logs)
    start_updated = isnothing(count) ? 1 : max(start_shifted - count, 1)
    stop_shifted = b._active_range.stop + length(logs)
    _kafka_update_active_range!(b; start=start_updated, stop=stop_shifted)
end

hasfirst(b::KafkaLogsBuffer) = isempty(b._logs) || (first(b._logs)._offset == 0)
haslast(b::KafkaLogsBuffer) =
    b._found_last && (isempty(b._logs) || b._active_range.stop == length(b._logs))

function _job_logs_kafka_async(
    f, auth::Authentication;
    jobname::AbstractString, next_offset::Integer, interrupt_channel::Channel,
)::Nothing
    # Note: we can't re-use the consumer_id from the previous request(s) because the timeout is
    # fixed once a consumer gets created, but we need to increase the timeout here.
    consumer_id = nothing
    while !isready(interrupt_channel)
        @debug "_job_logs_kafka_async[$jobname]: starting Kafka long poll" Dates.now()
        consumer_id, logs, job_is_done = _get_logs_kafka_parsed(
            auth, jobname; consumer_id, offset=next_offset, timeout=_KAFKA_DEFAULT_POLL_TIMEOUT
        )
        @debug "_job_logs_kafka_async[$jobname]: processing logs" Dates.now() length(logs)
        # If we found any logs, we call f() and also update next_offset so that we'd get the next
        # set of logs on the next loop iteration.
        if !isempty(logs)
            f(logs, job_is_done)
            next_offset = last(logs)._offset + 1
        end
        # In addition to check interrupt_channel, there are two ways the task can finish on its own:
        job_is_done && break
    end
end

function _get_logs_kafka_parsed(
    auth::Authentication,
    jobname::AbstractString;
    offset::Union{Integer, Nothing}=nothing,
    consumer_id::Union{Integer, Nothing}=nothing,
    timeout::Union{Integer, Nothing}=nothing,
)
    @debug "_get_logs_kafka_parsed($jobname): start REST call" _taskstamp() offset consumer_id timeout
    r = _get_job_logs_kafka_restcall(auth, jobname; offset, consumer_id, timeout)
    r.status == 200 || _throw_invalidresponse(r)
    json, json_str = _parse_response_json(r, Dict)
    consumer_id = _get_json(json, "consumer_id", Int)
    # If the Kafka endpoints want to return an empty list of log messages, it returns it
    # as an empty object (i.e. "logs": {}), rather than an empty array.
    logs = _get_json(json, "logs", Union{Dict, Vector})
    logmessages, jobdone = if isa(logs, Dict)
        if !isempty(logs)
            throw(JuliaHubError("Non-empty dictionary for logs\n$(json_str)"))
        end
        JobLogMessage[], false
    else
        # It is possible that the server returns rubbish log messages that we do not know how to
        # interpret, and we don't know how to reasonable convert them to JobLogMessage objects.
        # In that case, we loudly complain, and then refuse to recognize that message.
        # Note: this will likely cause a situation where you have missing offset values.
        parsed_logs = Vector{JobLogMessage}(undef, length(logs))
        parsed_logs_cursor = 0
        # It is possible for the last message to be a meta message that indicates that the job
        # has finished and that we should not expect any more messages. Although.. sometimes it can
        # also occur in a random place.. or there may be multiple meta messages.
        bottom_message = false
        for (i, log) in enumerate(logs)
            if !isa(log, Dict)
                @error "Invalid log message type $(typeof(log)) (at $i / $(length(logs)); omitting)" i log
                continue
            end
            # Any meta=bottom message we encounter will indicate that the job is finished. But if the meta
            # message is in the wrong place, we will throw a warning.
            if _kafka_is_last_message(log)
                bottom_message = true
                if i != length(logs)
                    @warn "Invalid meta=bottom message detected (at $i / $(length(logs)); omitting)" i log
                end
                continue
            end
            # TODO: this try catch is meant to catch bad log message construction. This should be done
            # via a nothing instead, so that coding errors would still throw.
            parsed_log = try
                JobLogMessage(_KafkaLogging(), log)
            catch e
                @error "Unable to construct a log message (at $i / $(length(logs)); omitting)" i log exception = (
                    e, catch_backtrace()
                )
                continue
            end
            # Only update parsed_logs_cursor when we actually "push" a new log, so that it would always
            # correspond to the true length of parsed_logs.
            parsed_logs_cursor += 1
            parsed_logs[parsed_logs_cursor] = parsed_log
        end
        # If some messages were omitted, we need to throw away some of the uninitialized elements
        # from the end of parsed_logs.
        resize!(parsed_logs, parsed_logs_cursor)
        parsed_logs, bottom_message
    end
    @debug "_get_logs_kafka_parsed($jobname): results parsed" _taskstamp() consumer_id length(logs) length(
        logmessages
    ) isempty(
        logmessages
    ) || (
        first(logmessages)._offset, last(logmessages)._offset
    ) jobdone
    return (; consumer_id, logs=logmessages, isdone=jobdone)
end

function _kafka_is_last_message(json::Dict)
    value = _get_json_or(json, "value", Dict, Dict())
    _meta = _get_json_or(value, "_meta", Bool, false)
    _end = get(value, "end", nothing)
    return _meta && (_end == "bottom")
end

function _get_job_logs_kafka_restcall(
    auth::Authentication,
    jobname::AbstractString;
    offset::Union{Integer, Nothing}=nothing,
    consumer_id::Union{Integer, Nothing}=nothing,
    timeout::Union{Integer, Nothing}=nothing,
)::_RESTResponse
    query = Dict{String, Any}(
        "jobname" => jobname
    )
    isnothing(offset) || (query["offset"] = offset)
    isnothing(consumer_id) || (query["consumer_id"] = consumer_id)
    # Note: timeout only has an effect if consumer_id is unset, since it set's the consumer's
    # request timeout.
    isnothing(timeout) || (query["timeout"] = timeout)
    return _restcall(auth, :GET, "juliaruncloud", "get_logs_v2"; query)
end
