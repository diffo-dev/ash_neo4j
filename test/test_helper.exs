# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

# Start the Bolt6 pool (Neo4j 2026.05 / Bolt 6.0) from the long-lived test_helper
# process so it survives the whole run. Bolty.start_link/1 links the pool to the
# calling process, so starting it from a per-test `setup` would tie its lifetime
# to a single test. Harmless when the pool is absent — `:bolt6` tests are
# excluded by default.
AshNeo4j.BoltyHelper.start_bolt6()

# `:cypher25` — needs a Neo4j ≥ 2025.06 server (the Bolt6 pool / 2026.05).
# `:bolt6` — reserved for tests that genuinely require the Bolt 6.0 protocol.
ExUnit.start(exclude: [:show_neo4j, :bolt6, :cypher25])
