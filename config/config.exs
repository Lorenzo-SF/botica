import Config

# Arrea sudo allowlist — scoped to the systemctl commands Botica's
# PostgreSQL/Redis batteries actually need to run during auto-repair.
# Removing `:no_sudo` from `validation_rules` would also allow
# `sudo rm -rf /`; the allowlist is the safer granular form
# (see arrea PR #7, ARRE-005).
config :arrea, :engine,
  sudo_allowlist: [
    "systemctl start postgresql",
    "systemctl start redis-server",
    "systemctl start redis",
    "systemctl restart postgresql",
    "systemctl restart redis-server",
    "systemctl restart redis",
    "systemctl stop postgresql",
    "systemctl stop redis-server",
    "systemctl stop redis"
  ]
