# Slidex

To start your Phoenix server:

- Run `mix setup` to install and set up dependencies
- Start the Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:5716`](http://localhost:5716) from your browser.

Development uses a local PostgreSQL database (`postgres`/`postgres` on
`localhost`, database `slidex_dev`); see `config/dev.exs`. The HTTP port
defaults to 5716 and can be overridden with `PORT`.

## Production

Slidex is deployed to the amignosis Hetzner VPS and served from
`https://slidex.greecex.org`. Runtime configuration is read from environment
variables (see `config/runtime.exs`): `DATABASE_URL`, `SECRET_KEY_BASE`,
`PHX_HOST`, `PHX_SERVER`, `PORT`, and `MAILGUN_API_KEY` / `MAILGUN_DOMAIN`
for email. Deploys run via GitHub Actions on push to `main`.
