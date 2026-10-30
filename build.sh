#!/usr/bin/env bash
set -o errexit
export MIX_ENV=prod

mix deps.get --only prod
mix compile

npm ci --include=dev --include=optional --prefix ./assets
npm run deploy --prefix ./assets
mix phx.digest

mix release --overwrite
mix ecto.migrate
