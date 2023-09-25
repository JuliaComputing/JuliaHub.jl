# Release notes

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## UNRELEASED

### Fixed

* Fixed the submission of application-type jobs. (#31, #32, #33)
* `JuliaHub.applications()` no longer throws a type error when the user has no registered and user applications. (#33)

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
