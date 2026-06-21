# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

# Dialyzer warnings deliberately ignored. Prefer fixing over ignoring — add an
# entry only for a genuine Dialyzer limitation or intentional design, each with
# a comment saying why.
[
  # The sandbox holder is a spawned process that loops forever (holding the test
  # transaction open until the test exits), so its function intentionally has no
  # local return. Correct by design, not a bug.
  {"lib/sandbox.ex", :no_return}
]
