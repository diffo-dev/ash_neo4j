<!-- 
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.1.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.0...v0.1.0) (2025-04-30)

### Features:
* initial version, read only

## [v0.1.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.0...v0.1.1) (2025-05-05)

### Features:
* create

### Bug Fixes:
* read arbitrary resource

## [v0.1.2](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.1...v0.1.2) (2025-05-23)

### Features:
* property types, duration, relate, destroy

## [v0.1.3](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.2...v0.1.3) (2025-05-24)

### Features:
* sort, offset, limit

## [v0.1.4](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.3...v0.1.4) (2025-05-28)

### Features:
* spark improvements

## [v0.1.5](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.4...v0.1.5) (2025-05-31)

### Features:
* logger
* upsert nodes
* optional label

## [v0.1.6](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.5...v0.1.6) (2025-06-02)

### Features:

* embedded resources
* nil attributes
* nil relationship attributes

## [v0.2.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.6...v0.2.0) (2025-06-05)

### Features:

* improved BoltxHelper
* create relate
* livebook

## [v0.2.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.0...v0.2.1) (2025-06-17)

### Features:

* many to many relationship (back to back has_many)
* has one relationship

## [v0.2.2](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.1...v0.2.2) (2025-06-26)

### Maintenance:

* refactored tests
* fixed Ash.Error.Unknown when filtering using contains
* fixed Ash.Error.Unknown in datalayer when relate not defined

## [v0.2.3](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.2...v0.2.3) (2025-07-10)

### Features:

* expression calculations
* unloaded attributes are Ash.NotLoaded
* improved metadata
* improved relate error messages
* improved relate verification

## [v0.2.4](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.3...v0.2.4) (2025-07-16)

### Features:

* support AshStateMachine
* improved enrichment
* query on relationship attribute
* create with multiple relationships

### Maintenance

* fixed Ash.Error.Unknown no function matching clause in AshNeo4j.Cypher.expression/4

## [v0.2.5](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.4...v0.2.5) (2025-07-21)

### Features:

* guard against destroy
* improved has_one and belongs_to enrichment
* improved logging

### Maintenance

* fixed destroy should fail when destination has allow_nil?: false

## [v0.2.6](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.5...v0.2.6) (2025-07-25)

### Maintenance

* fixed nested calculations with references are nil
* fixed cypher error when filtering on atom type
* fixed Ash.Error.Unknown when a delete is guarded
* fixed Ash.Error.Unknown invalid filter statement provided

## [v0.2.7](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.6...v0.2.7) (2025-08-03)

### Features

* relates node cypher avoids cartesian product warning

### Maintenance

* fixed Ash.Error.Unknown no result to unrelate nodes
* fixed create or update belongs_to on same resoruce adds rather than replaces
* fixed Ash.Error.Unknown no case clause matching on update
* fixed guard edge label regex
* fixed sorting not working
* fixed nested calculations with references are nil

## [v0.2.8](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.7...v0.2.8) (2025-08-14)

### Features

* relate destination node label
* independent relationships
* simplified dsl

### Maintenance

* fixed unexpected empty query result
* fixed has_many enrichment incorrect cypher
* fixed create with multiple relationships doesn't relate nodes

## [v0.2.9](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.8...v0.2.9) (2025-08-16)

### Maintenance

* fixed Ash.Error.Unknown when reading structs embedded in structs

## [v0.2.10](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.9...v0.2.10) (2025-09-09)

### Maintenance

* fixed update on_lookup relate on has_many exclusivity

## [v0.2.11](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.10...v0.2.11) (2025-10-13)

### Features

* REUSE compliant

### Fixes

* updated ash dependency for CVE-2025-48043 fix

## [v0.2.12](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.11...v0.2.12) (2025-11-18)

### Fixes

## [v0.2.13](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.12...v0.2.13) (2026-03-12)

### Features

* translate using attribute source (translate DSL removed)
* nodes are also labelled with domain label

### Fixes

* fixed dates and times not native

### Maintenance

* uses bolty at https://github.com/diffo-dev/bolty, a reluctant fork of boltx
* updated deps and tool versions
* improved info documenation

## [v0.2.14](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.13...v0.2.14) (2026-03-19)

### Fixes

* fix relationship enrichment inconsistent across neo4j versions

## [v0.2.15](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.14...v0.2.15) (2026-03-19)

### Fixes

* fix domain label incorrect

## [v0.3.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.15...v0.3.0) (2026-04-18)

This release changes the storage type for most types. Ash.Type dump_to_native/cast_stored are used where possible.T
String.Chars is no longer required and JSON blobs/Base64 are employed. Native Neo4j types are used except for datetime, instead we use ISO8601 strings to work around Neo4j 5.x incompatibility. There is no data migration supported.

### What's Changed
* 196 remove need for structs to implement stringchars by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/197
* reduced advertised capability, fixed calculations by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/198
* refactored transformers as persisters, split DataLayer and Resource Info by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/201
* updated deps and reinstated keyword tests by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/204
* fixed persister and improved verifier to verify all labels by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/205
* added encoding test and fixed json_encode for map by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/207
* added defensive casting, returning error tuple by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/209
* expression calculations in memory by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/210


## [v0.3.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.3.0...v0.3.1) (2026-04-23)

This release changes the storage type for Ash.Type.DateTime, Ash.Type.UtcDateTime and Ash.Type.UtcDateTimeUsec

### What's Changed
* use native neo4j 5.x datetime by @matt-beanland
