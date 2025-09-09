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

