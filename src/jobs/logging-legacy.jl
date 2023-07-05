struct _LegacyLogging <: _JobLoggingAPIVersion end

function JobLogMessage(::_LegacyLogging, json::Dict, offset::Integer)
    message = _get_json(json, "message", String)
    keywords = _get_json_or(json, "keywords", Dict, Dict{String, Any}())
    metadata = _get_json_or(json, "metadata", Dict, Dict{String, Any}())
    timestamp = if haskey(json, "timestamp")
        # Apparently timestamps are sometimes strings, sometimes integers..
        timestamp = _get_json(json, "timestamp", Union{String, Integer})
        # Timestamps apparently have a 'Z' at the end, which we'll need to
        # strip first.
        if isa(timestamp, AbstractString)
            _utc2localtz(Dates.DateTime(rstrip(timestamp, 'Z')))
        else
            # integer case, which is in milliseconds...
            _ms_utc2localtz(timestamp)
        end
    else
        nothing
    end
    eventId = _get_json_or(json, "eventId", String, nothing)
    JobLogMessage(;
        _offset=offset, timestamp, message, _metadata=metadata, _keywords=keywords,
        _legacy_eventId=eventId, _kafka_stream=nothing, _json=json,
    )
end

mutable struct _LegacyLogsBuffer <: AbstractJobLogsBuffer
    _lock::ReentrantLock
    _jobname::String
    _logs::Vector{JobLogMessage}
    _active_range::UnitRange{Int}
    _found_first::Bool
    _found_last::Bool
    _stream::Union{_JobLogTask, Nothing}
    _update_callback::Union{Base.Callable, Nothing}

    function _LegacyLogsBuffer(
        f::Base.Callable,
        auth::Authentication;
        jobname::AbstractString,
        offset::Union{Integer, Nothing},
        stream::Bool,
    )
        isnothing(offset) || (offset >= 0) ||
            throw(ArgumentError("Invalid `offset` value: $offset"))
        # We'll start by constructing a placeholder buffer object
        buffer = new(
            ReentrantLock(),
            jobname,
            JobLogMessage[], # empty _logs buffer
            1:0, # _active_range
            false, false, # _found_first/last
            nothing,
            f,
        )
        # We'll try to fetch some existing logs, just to figure out where we are
        # in the logs right now. If offset is give, we need to fetch all logs anyway,
        # so that we could set the active range appropriately. However, if offset is
        # not set, then we just do a single request, assume that it corresponds to
        # the last N logs, and put them in the buffer.
        if isnothing(offset)
            r = _get_job_logs_legacy(auth, jobname)
            if isempty(r.logs) && !r.found_top
                @warn "Invalid empty response from server"
            end
            buffer._found_first = r.found_top
            buffer._found_last = r.found_bottom
            prepend!(buffer._logs, r.logs)
            # The current "first" log message is set to one after the buffer. This makes
            # sure that we don't show any of the older (current) messages if the user
            # does newer! or a messages comes in via streaming.
            buffer._active_range = (length(buffer._logs) + 1):length(buffer._logs)
        else
            # If offset _is_ set, then we will fill all existing logs, and potentially
            # error if the offset value is bad.
            lock(buffer) do
                _job_logs_legacy_fill_buffer!(auth, buffer)
                # If there are no logs present, and offset=0, then that is fine. But for
                # non-zero offsets, we require the log message to be present.
                if (offset != 0) && length(buffer._logs) <= offset
                    throw(
                        InvalidRequestError(
                            "offset=$offset too large for $jobname, not enough logs"
                        ),
                    )
                end
                buffer._active_range = (offset + 1):offset
            end
        end
        # If streaming was requested, we start that up. Hopefully, doing it early, will avoid
        # missing any log messages if offset was set.
        stream && _job_logs_legacy_start_streaming!(auth, buffer)
        return buffer
    end
end

function Base.show(io::IO, ::MIME"text/plain", b::_LegacyLogsBuffer)
    printstyled(io, "_LegacyLogsBuffer"; bold=true)
    println(
        io, ": ", b._jobname, " (", length(b._active_range), " logs",
        isnothing(b._stream) ? "" : "; streaming",
        ")",
    )
    buffered_total = length(b._logs)
    buffered_start = b._active_range.start - 1
    buffered_stop = length(b._logs) - b._active_range.stop
    print(io, " buffer: Σ$buffered_total")
    print(io, " / -", buffered_start, (b._found_first ? " [F]" : ""))
    print(io, " / +", buffered_stop, (b._found_last ? " [F]" : ""))
    if !isempty(b.logs)
        println(io)
        _print_log_list(io, b.logs; nlines=_default_display_lines(io; adjust=6))
    end
end

# Forward lock() / unlock() to the buffer object.
Base.lock(b::_LegacyLogsBuffer) = lock(b._lock)
Base.unlock(b::_LegacyLogsBuffer) = unlock(b._lock)
function Base.lock(f, b::_LegacyLogsBuffer)
    lock(b)
    try
        return f()
    finally
        unlock(b)
    end
end

hasfirst(buffer::_LegacyLogsBuffer) = buffer._found_first && (buffer._active_range.start == 1)
haslast(buffer::_LegacyLogsBuffer) =
    buffer._found_last && (buffer._active_range.stop == length(buffer._logs))

_job_logs_active_logs(b::_LegacyLogsBuffer) = b._logs[b._active_range]
_job_logs_active_logs_view(b::_LegacyLogsBuffer) = @view(b._logs[b._active_range])

function _job_logs_update_active_range!(buffer::_LegacyLogsBuffer; start=nothing, stop=nothing)
    notify_user = false
    updated_start = if isnothing(start) || buffer._active_range.start == start
        buffer._active_range.start
    else
        notify_user = true
        start
    end
    updated_stop = if isnothing(stop) || buffer._active_range.stop == stop
        buffer._active_range.stop
    else
        notify_user = true
        stop
    end
    if notify_user
        buffer._active_range = updated_start:updated_stop
        _job_logs_notify_cb(buffer)
    end
    return nothing
end

function _job_logs_notify_cb(buffer::_LegacyLogsBuffer)
    try
        buffer._update_callback(buffer, @view(buffer._logs[buffer._active_range]))
    catch e
        @error "_job_logs_notify_cb: calling user callback errored" exception = (
            e, catch_backtrace()
        )
    end
    return nothing
end

_get_job_logs_legacy(auth::Authentication, buffer::_LegacyLogsBuffer; kwargs...) =
    _get_job_logs_legacy(auth, buffer._jobname; kwargs...)

function _get_job_logs_legacy(
    auth::Authentication,
    jobname::String;
    nentries=nothing,
    event_id=nothing,
    start_time=nothing,
    end_time=nothing,
)
    @debug "_get_job_logs_legacy: $jobname" nentries event_id start_time end_time
    # By default, the function retrieves the whole log file, but the (optional) keyword arguments allow for
    # pagination:
    #
    # - `nentries` is the maximum number of entries (<= 10_000) you want to query
    # - `start_time`/`end_time` is the timestamp that delimits which log messages (and in which direction) to query
    # - `event_id` is the event ID of the abovementioned delimiting log message
    #
    # The combination of the last two keyword arguments guarantees that no duplicate log messages are received.
    query = Pair{String, Any}[
        "log_output_type" => "content",
        "jobname" => jobname,
        "log_out_type" => "json"
    ]
    if start_time !== nothing
        if end_time !== nothing
            throw(ArgumentError("Only one of `end_time` and `start_time` may be provided."))
        end
        push!(query, "start_time" => start_time)
    end
    if end_time !== nothing
        if start_time !== nothing
            throw(ArgumentError("Only one of `end_time` and `start_time` may be provided."))
        end
        push!(query, "end_time" => end_time)
    end
    if nentries !== nothing
        push!(query, "nentries" => nentries)
    end
    if event_id !== nothing
        push!(query, "event_id" => event_id)
    end
    # Get the logs for `job` (or a job with ID `jobid`), returning a `Vector` of dictionaries. The log messages can contain the following keys:
    #
    # - `message::String`: Log message.
    # - `keywords::Dict`: Internal keywords are prefixed with `jrun_`; everything else is set by the user.
    # - `metadata::Dict`: Info about where the message was generated.
    # - `timestamp::Int` <-- the type here seems to be outdated, it's actually a String; and it's not always present
    # - `eventId::String`
    r = _restcall(auth, :GET, "juliaruncloud", "get_logs"; query)
    r.status == 200 || _throw_invalidresponse(r)
    # If the request was successful, we should be able to parse the logs. But if there was an error,
    # we might also get back a JSON with a success=false field.
    body = String(r.body)
    jb = JSON.parse(body)
    if jb isa Dict && !get(jb, "success", true)
        throw(
            JuliaHubError(
                "Downloading log content failed: `$(get(jb, "reason", get(jb, "message", "unknown error")))`",
            ),
        )
    end
    # The valid response is an escaped string of JSON.. so we strip the outer quotes and also
    # unescape the inner ones. The resulting string should parse as an JSON array.
    logs, _ = _parse_response_json(unescape_string(strip(body, '"')), Vector)
    # Parse the logs into JobLogMessages
    messages = Vector{JobLogMessage}(undef, length(logs))
    messages_length = 0
    found_top, found_bottom = false, false
    for (i, log) in enumerate(logs)
        message = try
            if _log_legacy_is_meta(log, "top")
                @debug "found top meta message" log
                i == 1 || @warn "top meta message in unexpected position: $i / $(length(logs))"
                found_top = true
                continue
            elseif _log_legacy_is_meta(log, "bottom")
                @debug "found bottom meta message" log
                i == length(logs) ||
                    @warn "top meta message in unexpected position: $i / $(length(logs))"
                found_bottom = true
                continue
            end
            JobLogMessage(_LegacyLogging(), log, -1)
        catch e
            # TODO: this try catch is meant to catch bad log message construction. This should be done
            # via a nothing instead, so that coding errors would still throw. _log_legacy_is_meta may also
            # currently throw, which should be avoided.
            @error "Unable to construct a log message (at $i / $(length(logs)); omitting)" i log exception = (
                e, catch_backtrace()
            )
            continue
        end
        messages_length += 1
        messages[messages_length] = message
    end
    # It's possible that we did not fully fill `messages`, so we resize it to its true length.
    resize!(messages, messages_length)
    return (; logs=messages, found_top, found_bottom)
end

# The log messages (may) have special _meta messages at the start and at the end.
# These have a `"_meta": true` field, and should have either `"end": "top"` (if first)
# or `"end": "bottom"` (if last message).
function _log_legacy_is_meta(log::Dict, s::AbstractString)
    haskey(log, "_meta") || return false
    if log["_meta"] !== true
        throw(JuliaHubError("""
        Invalid '_meta' field: $(log["_meta"]) (::$(typeof(log["_meta"])))
        $(sprint(show, MIME"text/plain"(), log))"""))
    end
    if !(get(log, "end", nothing) in ["top", "bottom"])
        throw(JuliaHubError("""
        Invalid or missing 'end' field in _meta message, expected "$s"
        $(sprint(show, MIME"text/plain"(), log))"""))
    end
    return log["end"] == s
end

function _job_logs_newer!(
    auth::Authentication, buffer::_LegacyLogsBuffer; count::Union{Integer, Nothing}=nothing
)
    jobname = buffer._jobname
    # If the buffer is streaming then this is a no-op
    isnothing(buffer._stream) || return nothing
    # If there are existing logs in the buffer then we may not have to fetch anything because
    # we have enough logs already in the buffer.
    if !isnothing(count) && !isempty(buffer._logs) &&
        buffer._active_range.stop + count <= length(buffer._logs)
        _job_logs_update_active_range!(buffer; stop=buffer._active_range.stop + count)
        return nothing
    end
    # It's possible that we have found the last message already, and so we shouldn't request
    # additional logs.
    if buffer._found_last
        # But it's also possible that active_range has not been updated, in which case we need to
        # do that. The case where the user is requesting fewer logs than are available is already
        # handled above, so we can safely just set the `stop` to the end of the buffer here.
        if buffer._active_range.stop != length(buffer._logs)
            _job_logs_update_active_range!(buffer; stop=length(buffer._logs))
        end
        return nothing
    end
    # It is possible that the buffer has no existing messages. In this case we first populate the
    # buffer with some messages. There should really be only one way we end up here: the buffer
    # was constructed when the job had no messages. But in that case, we should have still found
    # the top meta message.
    if isempty(buffer._logs)
        if !buffer._found_first
            # This should never happen, so we warn and no-op quit here.
            @warn "empty buffer and no top message"
            return nothing
        end
        # So to handle this case, we need to start fetching from the newest message and
        # go all the way back to the very first message.
        _job_logs_legacy_fill_buffer!(buffer)
        # If the buffer is still empty, we no-op return again. This means that the job
        # still hasn't produced any logs.
        isempty(buffer._logs) && return nothing
        # If not, then we assume we have now buffered all the current logs. We'll update the
        # active_range as needed, and then return.
        updated_stop = isnothing(count) ? length(buffer._logs) : min(count, length(buffer._logs))
        _job_logs_update_active_range!(buffer; start=1, stop=updated_stop)
        return nothing
    end
    # Finally, assuming we do have some logs, but not enough, we keep fetching new logs
    # until we don't find any more, find the last message, or have enough.
    while true
        reference_log = last(buffer._logs)
        start_time = _log_legacy_datetime_to_ms(reference_log.timestamp)
        event_id = reference_log._legacy_eventId
        r = JuliaHub._get_job_logs_legacy(auth, jobname; start_time, event_id)
        # If we have found the last log message, we'll mark the buffer done.
        if r.found_bottom
            buffer._found_last = true
        end
        # If there are no log messages, then we have reached the end of the currently
        # available logs, and we'll abort the fetch loop.
        isempty(r.logs) && break
        # If we did find some messages, we append them, and also update the user callback.
        append!(buffer._logs, r.logs)
        # We need to check if we found enough logs w.r.t. count, unless count=nothing,
        # in which case we want to go all the way to the end of the current logs.
        if isnothing(count)
            # If there is no `count` limit, then we just push the active range all the way
            # to the end and then carry on to the next iteration.
            _job_logs_update_active_range!(buffer; stop=length(buffer._logs))
        else
            # If we found enough logs, we update the active range and stop.
            # Otherwise, we carry on to the next loop.
            if buffer._active_range.stop + count <= length(buffer._logs)
                updated_stop = buffer._active_range.stop + count
                _job_logs_update_active_range!(buffer; stop=updated_stop)
                break
            else
                _job_logs_update_active_range!(buffer; stop=length(buffer._logs))
                count -= length(r.logs)
            end
        end
        # However, if we did find the last one, then we also stop.
        r.found_bottom && break
    end
end

# Fetches all the logs from the oldest buffered log all the way to the first log
# of the job.
function _job_logs_legacy_fill_buffer!(auth::Authentication, buffer::_LegacyLogsBuffer)
    while true
        end_time, event_id = if isempty(buffer._logs)
            nothing, nothing
        else
            reference_log = first(buffer._logs)
            _log_legacy_datetime_to_ms(reference_log.timestamp), reference_log._legacy_eventId
        end
        r = _get_job_logs_legacy(auth, buffer._jobname; end_time, event_id)
        # Since we haven't found the first message, we can't actually update the user.
        # So we don't update active range here.
        prepend!(buffer._logs, r.logs)
        if r.found_bottom
            buffer._found_last = true
        end
        if r.found_top
            buffer._found_first = true
            # If we found the first message, then we shouldn't do nay more requests.
            break
        end
        # We should never find an empty set of logs, but we'll handle it gracefully with
        # a warning.
        if isempty(r.logs)
            @warn "Empty set of logs" end_time event_id buffer
            break
        end
    end
end

function _job_logs_older!(
    auth::Authentication, buffer::_LegacyLogsBuffer; count::Union{Integer, Nothing}=nothing
)
    jobname = buffer._jobname
    # If there are existing logs in the buffer then we may not have to fetch anything because
    # we have enough logs already in the buffer.
    if !isnothing(count) && !isempty(buffer._logs) && buffer._active_range.start - count >= 1
        _job_logs_update_active_range!(buffer; start=buffer._active_range.start - count)
        return nothing
    end
    # Alternatively, it's possible that we have found the first message, and so we also
    # shouldn't request additional logs.
    if buffer._found_first
        # But it's also possible that active_range has not been updated, in which case we
        # still set the start to the start of the buffer. The case where the user requested
        # fewer logs than are in the buffer is handled by the previous `if`.
        if buffer._active_range.start != 1
            _job_logs_update_active_range!(buffer; start=1)
        end
        return nothing
    end
    # It is possible that the buffer has no existing messages. In this case we assume that
    # the buffer has been constructed with offset=nothing, i.e. that the active_range cursor
    # points to the _end_ of the current logs. If offset had been set, we should have some logs,
    # or, minimally, ._found_first should have been set. So if neither of those is true, we'll
    # do an argument-less request to figure out where we are with the job logs.
    #
    # The most common case where this might happen is when the buffer has been set to stream,
    # but no new messages have arrived via the stream.
    if isempty(buffer._logs)
        r = _get_job_logs_legacy(auth, jobname)
        buffer._found_first = r.found_top
        buffer._found_last = r.found_bottom
        if !isempty(r.logs)
            append!(buffer._logs, r.logs)
            _job_logs_update_active_range!(
                buffer;
                start=isnothing(count) ? 1 : length(buffer._logs) - count + 1,
                stop=length(buffer._logs),
            )
        else
            # It is possible that we don't find any messages (e.g. if the job has just started),
            # but in that case the _meta/top messages _should_ definitely be present. So let's
            # warn here (but otherwise be graceful).
            if !r.found_top
                @warn "No log messages found, but _meta/top message is also missing" r
            end
            # Generally though, if we still didn't find any messages, then that indicates that
            # the job still hasn't generated any. So we return. But we have now indicated that
            # we're at the start of the job.
            return nothing
        end
    end
    # If count is not enough, then we start fetching earlier logs, potentially multiple times.
    while true
        reference_log = first(buffer._logs)
        timestamp = _log_legacy_datetime_to_ms(reference_log.timestamp)
        r = JuliaHub._get_job_logs_legacy(
            auth, jobname;
            end_time=timestamp,
            event_id=reference_log._legacy_eventId
        )
        if isempty(r.logs)
            # TODO: If the logs are empty, then something has probably gone wrong
            @warn "Unexpected empty log list" r reference_log buffer
            break
        end
        # We'll prepend all the logs, but active_range changes depends on circumstances
        prepend!(buffer._logs, r.logs)
        buffer._found_first = r.found_top
        # If we found enough logs, then we don't have to do another loop. If not, we
        # declare all the existing and new logs to be valid, reduce count and carry on
        # with the next request. Only applicable when count was set though.
        updated_stop = buffer._active_range.stop + length(r.logs)
        if !isnothing(count)
            # buffer._active_range.start + length(r.logs) corresponds to the number of
            # "unrevealed" logs at the start of the buffer (after prepending the new ones).
            if buffer._active_range.start + length(r.logs) - count > 0
                updated_start = buffer._active_range.start + length(r.logs) - count
                _job_logs_update_active_range!(buffer; start=updated_start, stop=updated_stop)
                break
            end
            count -= length(r.logs) + buffer._active_range.start - 1
        end
        _job_logs_update_active_range!(buffer; start=1, stop=updated_stop)
        # But it is possible that we found the top message and also have to stop here
        r.found_top && break
    end
end

function _job_logs_legacy_start_streaming!(auth::Authentication, buffer::_LegacyLogsBuffer)
    if !isnothing(buffer._stream)
        @warn "Logs are already being streamed" buffer._jobname
        return nothing
    end
    # If we're not already streaming, we construct a new _JobLogTask
    jobname = buffer._jobname
    interrupt_channel = Channel{Nothing}(1)
    @debug "_job_logs_legacy_start_streaming!: starting websocket"
    lock(buffer) do
        # TODO: there might be a gap between the last buffered log and the first log message
        # that comes over the websocket. When the first websocket messages comes through, we
        # should fill the back with a standard get_logs request.
        t = @async _job_logs_legacy_websocket(auth, jobname) do ws, msg
            # It's possible that older! will find the last message in some situations (particularly
            # when streaming a finished job). In that case, we want to quit the websocket.
            if buffer._found_last
                @debug "_job_logs_legacy_start_streaming!: last message found already"
                close(ws)
                return nothing
            end
            # If the log task has been interrupt!-ed, we stop listening to the websocket.
            if isready(interrupt_channel)
                @debug "_job_logs_legacy_start_streaming!: user interrupt, closing websocket"
                close(ws)
                return nothing
            end
            # The websocket sends empty keep-alive-y messages. If we get any of those,
            # we just ignore it. But they do offer a moment for interrupts to take effect.
            if isempty(msg)
                @debug "Received a keepalive ($jobname)" _taskstamp()
                return nothing
            end
            # If the message wasn't empty, we assume that it is a valid JSON blob containing
            # a log message.
            msg, _ = _parse_response_json(msg, Dict)
            if _log_legacy_is_meta(msg, "top")
                @error "Unexpected `top` meta message streamed" msg
                return nothing
            end
            lock(buffer) do
                if _log_legacy_is_meta(msg, "bottom")
                    @debug "_job_logs_legacy_start_streaming!: found bottom message, finishing" msg
                    close(ws)
                    return nothing
                end
                log = try
                    previous_offset = isempty(buffer._logs) ? 0 : last(buffer._logs)._offset
                    JobLogMessage(_LegacyLogging(), msg, previous_offset + 1)
                catch e
                    @error "Unable to parse log message\n$msg" exception = (e, catch_backtrace())
                    return nothing
                end
                push!(buffer._logs, log)
                _job_logs_update_active_range!(buffer; stop=length(buffer._logs))
            end
            return nothing
        end
        buffer._stream = _JobLogTask(t, interrupt_channel)
    end
    return nothing
end

function _job_logs_legacy_websocket(f::Function, auth::Authentication, jobname::AbstractString)
    @debug "_job_log_websocket_legacy: starting task ($jobname)" _taskstamp()
    https_url = _url(auth, "ws", "stream_logs")
    ws_url = replace(https_url, r"^http://" => "ws://")
    ws_url = replace(https_url, r"^https://" => "wss://")
    @_httpcatch HTTP.WebSockets.open(
        ws_url;
        headers=_authheaders(auth),
        query=[
            "jobname" => jobname,
            "refresh_interval" => 1,
            "log_out_type" => "json",
        ],
    ) do ws
        for msg in ws
            @debug "_job_log_websocket_legacy: message from websocket ($jobname)" _taskstamp() msg
            f(ws, msg)
        end
    end
    @debug "_job_logs_legacy_websocket: task finishing ($jobname)" _taskstamp()
    return nothing
end

# The timestamp fields for the olds logs are sometimes strings, sometimes integers (unix
# timestamp in ms). Since the filtering functions always assume an integer input, we have
# this helper to convert any "timestamp" field to an integer.
function _log_legacy_datetime_to_ms(timestamp::AbstractString)
    timestamp = rstrip(timestamp, 'Z')
    return _log_legacy_datetime_to_ms(Dates.DateTime(timestamp))
end
function _log_legacy_datetime_to_ms(timestamp::Dates.DateTime)
    t_s = Dates.datetime2unix(timestamp)
    return round(Int, 1000 * t_s)
end
function _log_legacy_datetime_to_ms(timestamp::TimeZones.ZonedDateTime)
    datetime_utc = Dates.DateTime(TimeZones.astimezone(timestamp, TimeZones.tz"UTC"))
    return _log_legacy_datetime_to_ms(datetime_utc)
end
_log_legacy_datetime_to_ms(timestamp::Integer) = timestamp
