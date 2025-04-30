import Config

config :boltx, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: ""],
  user_agent: "boltxTest/1",
  pool_size: 15,
  max_overflow: 3,
  prefix: :default,
  name: Bolt
