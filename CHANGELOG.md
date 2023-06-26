# Release notes

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Version v0.1.2 - 2023-06-26

### Fixed

* If TimeZones.jl fails to determine the system's timezone, JuliaHub.jl now gracefully falls back to UTC to represent dates and times. (#7)

## Version v0.1.1 - 2023-06-24

### Added

* The `JuliaHub.download_job_file` function now returns the path of the relevant local file. (#3)

### Fixed

* Jobs with files that have missing data are now handled gracefully by defaulting the `.size` property to `0` and `.hash` property to `nothing`. (#3)
* Information about dataset versions can now be accessed via the the `.versions` property of a `Dataset` object. (#2)
* The automatic backend API version detection is now more reliable in some edge cases. (#1)

## Version v0.1.0 - 2023-06-20

Initial package release.
