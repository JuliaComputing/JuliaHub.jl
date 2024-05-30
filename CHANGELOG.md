# Release notes

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

* The `JuliaHub.submit_job` function now allows submitting jobs that expose ports (via the `expose` argument). Related to that, the new `JuliaHub.request` function offers a simple interface for constructing authenticated HTTP.jl requests against the job, and the domain name of the job can be accessed via the new `.hostname` property of the `Job` object. (#14, #52)

## Version v0.1.9 - 2024-03-13

### Fixed

* `JuliaHub.nodespec` now correctly prioritizes the GPU, CPU, and memory counts, rather than the hourly price, when picking a "smallest node for a given spec". (#49)

## Version v0.1.8 - 2024-02-21

### Added

* The progress output printing in `JuliaHub.upload_dataset` can now be disabled by setting `progress=false`. (#48)

## Version v0.1.7 - 2024-01-22

### Fixed

* `JuliaHub.datasets` and `JuliaHub.dataset` now handle problematic backend responses more gracefully. (#46)

## Version v0.1.6 - 2023-11-27

### Fixed

* `JuliaHub.appbundle`, when it has to generate a `Project.toml` file, now correctly includes it in the appbundle tarball. (#44)
* `JuliaHub.appbundle` now works with relative paths such as `"."`. (#44)

## Version v0.1.5 - 2023-09-27

### Added

* The job submission APIs now support jobs with no time limit, and also can be used to submit jobs that trigger system image builds. (#28)

### Fixed

* Fixed the submission of application-type jobs. (#31, #32, #33, #35)
* `JuliaHub.applications()` no longer throws a type error when the user has no registered and user applications. (#33)
* Fixed the `show(io, x)` methods for `ComputeConfig` and `NodeSpec`. (#34)

## Version v0.1.4 - 2023-08-21

### Fixed

* `upload_dataset` and `download_dataset` no longer use the deprecated do-syntax to call the `rclone` binary. (#18)

## Version v0.1.3 - 2023-07-17

### Changed

* The `name` keyword argument to `submit_job` has been deprecated and replaced with `alias`. (#13)

### Fixed

* `extend_job` now correctly handles the `200` but `success: false` response. (#13)
* An assortment of small bugfixes revealed by JET. (#9) (#12)

### Tests

* The test suite now runs successfully when the package is `Pkg.add`ed and the package files have only read-only permissions. (#11)

## Version v0.1.2 - 2023-06-26

### Fixed

* If TimeZones.jl fails to determine the system's timezone, JuliaHub.jl now gracefully falls back to UTC to represent dates and times. (#7)

## Version v0.1.1 - 2023-06-24

### Changed

* The `JuliaHub.download_job_file` function now returns the path of the relevant local file. (#3)

### Fixed

* Jobs with files that have missing data are now handled gracefully by defaulting the `.size` property to `0` and `.hash` property to `nothing`. (#3)
* Information about dataset versions can now be accessed via the the `.versions` property of a `Dataset` object. (#2)
* The automatic backend API version detection is now more reliable in some edge cases. (#1)

## Version v0.1.0 - 2023-06-20

Initial package release.
