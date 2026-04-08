# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

import Config

level =
  if System.get_env("DEBUG") do
    :debug
  else
    :info
  end

config :bolty, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  versions: [5.4],
  user_agent: "boltyTest/1",
  pool_size: 15,
  max_overflow: 3,
  prefix: :default,
  name: Bolt,
  log: true,
  log_hex: true,
  level: level

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\n"
