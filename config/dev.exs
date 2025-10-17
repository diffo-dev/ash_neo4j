# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

import Config

config :boltx, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  user_agent: "boltxTest/1",
  pool_size: 15,
  max_overflow: 3,
  prefix: :default,
  name: Bolt,
  log: true,
  log_hex: true

config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/diffo-dev/ash_neo4j",
  types: [
    # Makes an allowed commit type called `tidbit` that is not
    # shown in the changelog
    tidbit: [
      hidden?: true
    ],
    # Makes an allowed commit type called `important` that gets
    # a section in the changelog with the header "Important Changes"
    important: [
      header: "Important Changes"
    ]
  ],
  tags: [
    # Only add commits to the changelog that has the "backend" tag
    allowed: ["backend"],
    # Filter out or not commits that don't contain tags
    allow_untagged?: true
  ],
  # Instructs the tool to manage your mix version in your `mix.exs` file
  # See below for more information
  manage_mix_version?: true,
  # Instructs the tool to manage the version in your README.md
  # Pass in `true` to use `"README.md"` or a string to customize
  manage_readme_version: "README.md",
  version_tag_prefix: "v"

level =
  if System.get_env("DEBUG") do
    :debug
  else
    :info
  end

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\n"
