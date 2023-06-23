# Release notes

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

* The `JuliaHub.download_job_file` function now returns the path of the relevant local file. (#3)

### Fixed

* Jobs with files that have missing data are now handled gracefully by defaulting the `.size` property to `0` and `.hash` property to `nothing`. (#3)

## Version v0.1.0 - 2023-06-20

Initial package release.
