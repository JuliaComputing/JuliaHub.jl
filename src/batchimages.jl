"""
    struct BatchImage

Represents an available JuliaHub batch job image. These can be passed to [`BatchJob`](@ref)
to specify which underlying job image will be used for the job.

A list of available batch images can be accessed with [`batchimages`](@ref) and specific images
can be constructed with [`batchimage`](@ref).

$(_DOCS_no_constructors_admonition)

See also: [`batchimages`](@ref), [`batchimage`](@ref), [`BatchJob`](@ref), [`script`](@ref),
[`appbundle`](@ref).
"""
Base.@kwdef struct BatchImage
    product::String
    image::String
    _cpu_image_key::Union{String, Nothing}
    _gpu_image_key::Union{String, Nothing}
    _image_tag::Union{String, Nothing}
    _image_sha::Union{String, Nothing}
    _is_product_default::Bool
    _interactive_product_name::Union{String, Nothing}
end

function Base.show(io::IO, image::BatchImage)
    print(io, "JuliaHub.batchimage(")
    print(io, '"', image.product, "\", ")
    print(io, '"', image.image, '"')
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", image::BatchImage)
    printstyled(io, typeof(image), ": "; bold=true)
    print(io, '\n', " product: ", image.product)
    print(io, '\n', " image: ", image.image)
    isnothing(image._cpu_image_key) || print(io, "\n CPU image: ", image._cpu_image_key)
    isnothing(image._gpu_image_key) || print(io, "\n GPU image: ", image._gpu_image_key)
    isnothing(image._image_tag) || print(io, ":$(image._image_tag)")
    isnothing(image._image_sha) || print(io, ":$(image._image_sha)")
    if !isnothing(image._interactive_product_name)
        print(io, "\n Features:")
        print(io, "\n  - Expose Port: ✓")
    end
end

# This value is used in BatchImages objects when running against older JuliaHub
# instances where products do not exist as a concept. "Legacy" here referes to that
# it is using a "legacy API" or "legacy JuliaHub version".
const _LEGACY_PRODUCT_NAME = "@legacy"
const _DOCS_legacy_batch_note = """
!!! note "Batch images on older instances"

    When using the package with an older JuliaHub instance (<= 6.1), the non-default batch images
    show up with `$(_LEGACY_PRODUCT_NAME)` as the product name. This indicates that the package
    is using an older API, and not that the images themselves are outdated.
"""

"""
    JuliaHub.batchimages([product::AbstractString]; [auth::Authentication]) -> Vector{BatchImage}

Return the list of all batch job images available to the currently authenticated user, as a list of
[`BatchImage`](@ref) objects. These can be passed to [`BatchJob`](@ref).

Optionally, by passing a product identifier, the list can be narrowed down to images available for
that specific product.

$(_DOCS_legacy_batch_note)

See also: [`BatchImage`](@ref), [`batchimage`](@ref), [`BatchJob`](@ref), [`script`](@ref),
[`appbundle`](@ref).
"""
function batchimages(
    product::Union{AbstractString, Nothing}=nothing; auth::Authentication=__auth__()
)
    images = if auth._api_version >= v"0.0.1"
        _batchimages_62(auth)
    else
        _batchimages_legacy(auth)
    end
    # If the user specified the product, we filter out the where the product id does not match
    if !isnothing(product)
        filter!(i -> i.product == product, images)
    end
    return images
end

"""
    JuliaHub.batchimage(
        [product::AbstractString, [image::AbstractString]];
        throw::Bool=true, [auth::Authentication]
    ) -> BatchImage

Pick a product job batch image from the list of all batch image, returning a [`BatchImage`](@ref) object.
If `image` is omitted, it will return the default image corresponding to `product`. If `product` is omitted as
well, it will return the default image of the instance (generally the standard Julia batch image).

Will throw an [`InvalidRequestError`](@ref) if the specified image can not be found. If `throw=false`,
it will return `nothing` instead in this situation.

$(_DOCS_legacy_batch_note)

See also: [`BatchImage`](@ref), [`batchimages`](@ref), [`BatchJob`](@ref), [`script`](@ref),
[`appbundle`](@ref).
"""
function batchimage end

function batchimage(
    product::AbstractString="standard-batch"; throw::Bool=true, auth::Authentication=__auth__()
)
    images = batchimages(product; auth)
    isempty(images) && return _throw_or_nothing(; msg="No such product: $(product)", throw)
    # Now check that a default image exists
    filter!(image -> image._is_product_default, images)
    if isempty(images)
        return _throw_or_nothing(; msg="No default image for product: $(product)", throw)
    elseif length(images) >= 2
        Base.throw(JuliaHubError("""
        Multiple default images configured for product: $(product)
        You can work around this issue by exactly specifying the image."""))
    end
    return only(images)
end

function batchimage(
    product::AbstractString,
    image::AbstractString;
    throw::Bool=true,
    auth::Authentication=__auth__(),
)
    images = batchimages(; auth)
    for i in images
        i.product == product && i.image == image && return i
    end
    return _throw_or_nothing(;
        msg="No such (product, image) combination '($(product), $(image))'", throw
    )
end

function _batchimages_legacy(auth::Authentication)
    r = _restcall(auth, :GET, "juliaruncloud", "get_image_options")
    if r.status == 200
        try
            json = JSON.parse(String(r.body))
            if json["success"] && haskey(json, "image_options")
                image_options = json["image_options"]
                default_options = [
                    Dict(
                        "attrvalue" => "",
                        "attrdisplay" => true,
                        "attrid" => "sysimg",
                        "attrname" => "Image",
                        "attrchoices" => [
                            Dict(
                                "price" => 0.0,
                                "value" => "",
                                "text" => "Default",
                            ),
                        ],
                    ),
                ]
                # FIXME: This should return the whole vector
                images_json = if image_options isa Dict
                    get(
                        get(image_options, "batchjob", default_options), 1, default_options[1]
                    )
                else
                    default_options[1]
                end
                return map(images_json["attrchoices"]) do image
                    if isempty(image["value"]) && image["text"] in ("Julia", "Default")
                        return BatchImage(;
                            product="standard-batch", image="Julia",
                            _cpu_image_key="julia", _gpu_image_key="julia",
                            _is_product_default=true,
                        )
                    end
                    return BatchImage(;
                        product=_LEGACY_PRODUCT_NAME, image=image["text"],
                        _cpu_image_key=image["value"], _gpu_image_key=image["value"],
                        _is_product_default=false,
                    )
                end
            end
        catch e
            throw(JuliaHubError("Unexpected answer received.", e, catch_backtrace()))
        end
    end
    return _throw_invalidresponse(r)
end

function _api_product_image_groups(auth::Authentication)
    r = _restcall(auth, :GET, "juliaruncloud", "product_image_groups")
    r.status == 200 || _throw_invalidresponse(r)
    return _parse_response_json(r, Dict)
end

function _product_image_groups(auth::Authentication)
    r_json, r_json_str = _api_product_image_groups(auth)
    image_groups = _get_json(r_json, "image_groups", Dict)
    # Double check that the returned JSON is correct
    image_groups = map(collect(pairs(image_groups))) do (image_group, images)
        if !isa(images, Vector)
            msg = """
            Invalid JSON returned by the server: value for '$(image_group)' not a list
            $(r_json_str)
            """
            throw(JuliaHubError(msg))
        end
        images = _group_images(images; image_group)
        image_group => images
    end
    return Dict(image_groups...)
end

Base.@kwdef mutable struct _ImageKeys
    error::Bool = false
    isdefault::Bool = false
    cpu::Union{String, Nothing} = nothing
    gpu::Union{String, Nothing} = nothing
    tag::Union{String, Nothing} = nothing
    sha::Union{String, Nothing} = nothing
end

function _group_images(images; image_group::AbstractString)
    # The key here is the display name of the image group entry,
    # which should be unique.
    grouped_images = Dict{String, _ImageKeys}()
    for image in images
        if !isa(image, Dict)
            msg = """
            Invalid JSON returned by the server: image value is not an object
             image_group = $(image_group)
             image = $(image)
            """
            throw(JuliaHubError(msg))
        end
        image_key_name = _get_json(image, "image_key_name", String)
        display_name = _get_json(image, "display_name", String)
        tag = _get_json_or(image, "image_tag", Union{String, Nothing})
        sha = _get_json_or(image, "image_sha", Union{String, Nothing})
        image_type = _parse_image_group_entry_type(image)
        isnothing(image_type) && continue # invalid image type will return a nothing, which we will ignore
        imagekeys = get!(
            grouped_images, display_name, _ImageKeys(; isdefault=image_type.isdefault, tag, sha)
        )
        # If this image key set is already problematic, no point in checking further
        imagekeys.error && continue
        # We make sure that there are no conflicts with base- and option- image types
        if imagekeys.isdefault !== image_type.isdefault
            @warn "Default image confusion for '$(display_name)' in group '$(image_group)'. Omitting image." image imagekeys
            imagekeys.error = true
            continue
        end
        # We'll weed out any duplicate image keys for the same (image_group, display_name) pairs
        # (but note that image keys for GPUs and CPUs will be different).
        if image_type.gpu
            if !isnothing(imagekeys.gpu)
                @warn "Duplicate *-gpu image for '$(display_name)' in group '$(image_group)'. Omitting image." image
                imagekeys.error = true
                continue
            end
            imagekeys.gpu = image_key_name
        else
            if !isnothing(imagekeys.cpu)
                @warn "Duplicate *-cpu image for '$(display_name)' in group '$(image_group)'. Omitting image." image
                imagekeys.error = true
                continue
            end
            imagekeys.cpu = image_key_name
        end
    end
    # We'll filter out any errors
    grouped_images = filter(
        ((display_name, keys)::Pair) -> !keys.error,
        collect(grouped_images),
    )
    # We'll sort them such that default group comes first (note: false < true, so we flip it)
    sort(grouped_images; by=((display_name, keys)::Pair) -> (!keys.isdefault, display_name))
end

function _parse_image_group_entry_type(image::Dict)
    image_type = _get_json(image, "type", String)
    m = match(r"(base|option)-(cpu|gpu)", image_type)
    if isnothing(m)
        @warn "Invalid image type: $(image_type)" image
        return nothing
    end
    return (; isdefault=(m[1] == "base"), gpu=(m[2] == "gpu"))
end

function _is_batch_app(app::DefaultApp)
    # In terms of JuliaHub <= 6.1 compat, this function should always return
    # false for all apps in 6.1 and below because the apps/default endpoint does not
    # return compute_type_name or input_type_name fields.
    compute_type = get(app._json, "compute_type_name", nothing)
    input_type = get(app._json, "input_type_name", nothing)
    compute_type in ("batch", "singlenode-batch") && (input_type == "userinput")
end

function _is_interactive_batch_app(app::DefaultApp)
    # Like _is_batch_app, this should return false for JuliaHub <= 6.1
    compute_type = get(app._json, "compute_type_name", nothing)
    input_type = get(app._json, "input_type_name", nothing)
    compute_type in ("distributed-interactive",) && (input_type == "userinput")
end

function _batchimages_62(auth::Authentication)
    image_groups = _product_image_groups(auth)
    batchapps, interactiveapps = let apps = _apps_default(auth)
        filter(_is_batch_app, apps), filter(_is_interactive_batch_app, apps)
    end
    batchimages = map(batchapps) do app
        product_name = app._json["product_name"]
        image_group = app._json["image_group"]
        images = get(image_groups, image_group, [])
        if isempty(images)
            @warn "Invalid image_group '$image_group' for '$product_name'" app
        end
        matching_interactive_app = filter(interactiveapps) do app
            get(app._json, "image_group", nothing) == image_group
        end
        interactive_product_name = if length(matching_interactive_app) > 1
            # If there are multiple interactive products configured for a batch product
            # we issue a warning and disable the 'interactive' compute for it (i.e. the user
            # won't be able to start jobs that require a port to be exposed until the configuration
            # issue is resolved).
            @warn "Multiple matching interactive apps for $(app)" image_group matches =
                matching_interactive_app
            nothing
        elseif isempty(matching_interactive_app)
            # If we can't find a matching 'distributed-interactive' product, we disable the
            # ability for the user to expose a port with this image.
            nothing
        else
            only(matching_interactive_app)._json["product_name"]
        end
        map(images) do (display_name, imagekey)
            BatchImage(;
                product                   = product_name,
                image                     = display_name,
                _cpu_image_key            = imagekey.cpu,
                _gpu_image_key            = imagekey.gpu,
                _is_product_default       = imagekey.isdefault,
                _interactive_product_name = interactive_product_name,
                _image_tag                = imagekey.tag,
                _image_sha                = imagekey.sha,
            )
        end
    end
    return vcat(batchimages...)
end
