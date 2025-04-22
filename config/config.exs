import Config

config :ash, :validate_domain_resource_inclusion?, false
config :ash, :validate_domain_config_inclusion?, false
config :ash, :missed_notifications, :ignore

import_config "#{Mix.env()}.exs"
