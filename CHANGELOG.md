# Release notes

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Version [v0.1.14] - 2025-06-11

### Added

* Support for displaying and submitting batch image options with tags when working with JuliaHub instances v6.10 and above. ([#94])

### Experimental

* There is now _experimental_ support for registering Julia packages in a JuliaHub package registry. ([#96])

## Version [v0.1.13] - 2025-04-28

### Fixed

* Setting `JULIAHUB_PROJECT_UUID` to an empty (or whitespace-only) string is now treated the same as unsetting it. ([#92])

## Version [v0.1.12] - 2025-04-25

### Added

* With JuliaHub instances v6.9 and above, JuliaHub.jl now supports project-dataset operations. ([#15], [#82])

  This includes the following new features:

  - Authentication objects can now be associated with projects.
    If the `JULIAHUB_PROJECT_UUID` environment variable is set, JuliaHub.jl will pick it up automatically..
  - The `project_dataset` and `project_datasets` functions allow for listing datasets attached to a project.
  - `upload_project_dataset` can be used to upload a new version of a dataset.

* All the public API names are now correctly marked `public` in Julia 1.11 and above. ([#83])

### Changed

* The string `repr` of `DatasetVersion` (e.g. `dataset.versions`) is now valid Julia code. ([#84])
* `JuliaHub.authenticate` will now fall back to force-authentication if the token in an existing `auth.toml` file is found to be invalid during authentication. ([#86])

### Fixed

* The `JuliaHub.update_dataset` function now correctly accepts the `license=(:fulltext, ...)` argument. ([#74])

## Version [v0.1.11] - 2024-06-27

### Added

* The `JuliaHub.authenticate` function now supports a two-argument form, where you can pass the JuliaHub token in directly, bypassing interactive authentication. ([#58])
* The `JuliaHub.submit_job` function now allows submitting jobs that expose ports (via the `expose` argument). Related to that, the new `JuliaHub.request` function offers a simple interface for constructing authenticated HTTP.jl requests against the job, and the domain name of the job can be accessed via the new `.hostname` property of the `Job` object. ([#14], [#52])

## Version [v0.1.10] - 2024-05-31

### Changed

* When submitting an appbundle with the two-argument `JuliaHub.appbundle(bundle_directory, codefile)` method, JuliaHub.jl now ensures that `@__DIR__` `@__FILE`, and `include()` in the user code now work correctly. There is a subtle behavior change due to this, where now the user script _must_ be present within the uploaded appbundle tarball (previously it was possible to use a file that would get filtered out by `.juliabundleignore`). ([#37], [[#53]])

## Version [v0.1.9] - 2024-03-13

### Fixed

* `JuliaHub.nodespec` now correctly prioritizes the GPU, CPU, and memory counts, rather than the hourly price, when picking a "smallest node for a given spec". ([#49])

## Version [v0.1.8] - 2024-02-21

### Added

* The progress output printing in `JuliaHub.upload_dataset` can now be disabled by setting `progress=false`. ([#48])

## Version [v0.1.7] - 2024-01-22

### Fixed

* `JuliaHub.datasets` and `JuliaHub.dataset` now handle problematic backend responses more gracefully. ([#46])

## Version [v0.1.6] - 2023-11-27

### Fixed

* `JuliaHub.appbundle`, when it has to generate a `Project.toml` file, now correctly includes it in the appbundle tarball. ([#44])
* `JuliaHub.appbundle` now works with relative paths such as `"."`. ([#44])

## Version [v0.1.5] - 2023-09-27

### Added

* The job submission APIs now support jobs with no time limit, and also can be used to submit jobs that trigger system image builds. ([#28])

### Fixed

* Fixed the submission of application-type jobs. ([#31], [#32], [#33], [#35])
* `JuliaHub.applications()` no longer throws a type error when the user has no registered and user applications. ([#33])
* Fixed the `show(io, x)` methods for `ComputeConfig` and `NodeSpec`. ([#34])

## Version [v0.1.4] - 2023-08-21

### Fixed

* `upload_dataset` and `download_dataset` no longer use the deprecated do-syntax to call the `rclone` binary. ([#18])

## Version [v0.1.3] - 2023-07-17

### Changed

* The `name` keyword argument to `submit_job` has been deprecated and replaced with `alias`. ([#13])

### Fixed

* `extend_job` now correctly handles the `200` but `success: false` response. ([#13])
* An assortment of small bugfixes revealed by JET. ([#9]) ([#12])

### Tests

* The test suite now runs successfully when the package is `Pkg.add`ed and the package files have only read-only permissions. ([#11])

## Version [v0.1.2] - 2023-06-26

### Fixed

* If TimeZones.jl fails to determine the system's timezone, JuliaHub.jl now gracefully falls back to UTC to represent dates and times. ([#7])

## Version [v0.1.1] - 2023-06-24

### Changed

* The `JuliaHub.download_job_file` function now returns the path of the relevant local file. ([#3])

### Fixed

* Jobs with files that have missing data are now handled gracefully by defaulting the `.size` property to `0` and `.hash` property to `nothing`. ([#3])
* Information about dataset versions can now be accessed via the the `.versions` property of a `Dataset` object. ([#2])
* The automatic backend API version detection is now more reliable in some edge cases. ([#1])

## Version [v0.1.0] - 2023-06-20

Initial package release.


<!-- Links generated by Changelog.jl -->

[v0.1.0]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.0
[v0.1.1]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.1
[v0.1.2]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.2
[v0.1.3]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.3
[v0.1.4]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.4
[v0.1.5]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.5
[v0.1.6]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.6
[v0.1.7]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.7
[v0.1.8]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.8
[v0.1.9]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.9
[v0.1.10]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.10
[v0.1.11]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.11
[v0.1.12]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.12
[v0.1.13]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.13
[v0.1.14]: https://github.com/JuliaComputing/JuliaHub.jl/releases/tag/v0.1.14
[#1]: https://github.com/JuliaComputing/JuliaHub.jl/issues/1
[#2]: https://github.com/JuliaComputing/JuliaHub.jl/issues/2
[#3]: https://github.com/JuliaComputing/JuliaHub.jl/issues/3
[#7]: https://github.com/JuliaComputing/JuliaHub.jl/issues/7
[#9]: https://github.com/JuliaComputing/JuliaHub.jl/issues/9
[#11]: https://github.com/JuliaComputing/JuliaHub.jl/issues/11
[#12]: https://github.com/JuliaComputing/JuliaHub.jl/issues/12
[#13]: https://github.com/JuliaComputing/JuliaHub.jl/issues/13
[#14]: https://github.com/JuliaComputing/JuliaHub.jl/issues/14
[#15]: https://github.com/JuliaComputing/JuliaHub.jl/issues/15
[#18]: https://github.com/JuliaComputing/JuliaHub.jl/issues/18
[#28]: https://github.com/JuliaComputing/JuliaHub.jl/issues/28
[#31]: https://github.com/JuliaComputing/JuliaHub.jl/issues/31
[#32]: https://github.com/JuliaComputing/JuliaHub.jl/issues/32
[#33]: https://github.com/JuliaComputing/JuliaHub.jl/issues/33
[#34]: https://github.com/JuliaComputing/JuliaHub.jl/issues/34
[#35]: https://github.com/JuliaComputing/JuliaHub.jl/issues/35
[#37]: https://github.com/JuliaComputing/JuliaHub.jl/issues/37
[#44]: https://github.com/JuliaComputing/JuliaHub.jl/issues/44
[#46]: https://github.com/JuliaComputing/JuliaHub.jl/issues/46
[#48]: https://github.com/JuliaComputing/JuliaHub.jl/issues/48
[#49]: https://github.com/JuliaComputing/JuliaHub.jl/issues/49
[#52]: https://github.com/JuliaComputing/JuliaHub.jl/issues/52
[#53]: https://github.com/JuliaComputing/JuliaHub.jl/issues/53
[#58]: https://github.com/JuliaComputing/JuliaHub.jl/issues/58
[#74]: https://github.com/JuliaComputing/JuliaHub.jl/issues/74
[#82]: https://github.com/JuliaComputing/JuliaHub.jl/issues/82
[#83]: https://github.com/JuliaComputing/JuliaHub.jl/issues/83
[#84]: https://github.com/JuliaComputing/JuliaHub.jl/issues/84
[#86]: https://github.com/JuliaComputing/JuliaHub.jl/issues/86
[#92]: https://github.com/JuliaComputing/JuliaHub.jl/issues/92
[#94]: https://github.com/JuliaComputing/JuliaHub.jl/issues/94
[#96]: https://github.com/JuliaComputing/JuliaHub.jl/issues/96
