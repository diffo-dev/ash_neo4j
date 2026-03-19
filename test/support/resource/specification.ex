# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Specification do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    guard [
      {:SPECIFIES, :outgoing, :Service},
      {:SPECIFIES, :outgoing, :Resource}
    ]
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      primary? true
      accept [:name, :type, :href, :major_version, :minor_version, :patch_version, :tmf_version]
      load [:version]
    end

    read :get_latest do
      description "gets the specification of the given name with the highest major version"
      get? true

      argument :query, :ci_string do
        description "Return only specifications with names including the given value."
      end

      prepare build(limit: 1, sort: [major_version: :desc])
      filter expr(contains(name, ^arg(:query)))
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :href, :string, public?: true
    attribute :name, :string, public?: true
    attribute :type, :atom, constraints: [one_of: [:service, :resource]], public?: true
    attribute :major_version, :integer, default: 1, public?: true, source: :versionMajor
    attribute :minor_version, :integer, default: 0, public?: true, source: :versionMinor
    attribute :patch_version, :integer, default: 0, public?: true, source: :versionPatch
    attribute :tmf_version, :integer, default: 4, public?: true
  end

  calculations do
    calculate :version, :string, expr("v" <> major_version <> "." <> minor_version <> "." <> patch_version)
  end

  preparations do
    prepare build(
              load: [:version],
              sort: [name: :asc, major_version: :desc]
            )
  end
end
