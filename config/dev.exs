import Config

config :ex4j, Bolt,
  url: "bolt://localhost:7687",
  auth: [username: "neo4j", password: ""],
  pool_size: 10,
  max_overflow: 2,
  queue_interval: 500,
  queue_target: 1500,
  prefix: :default,
  ssl: false
