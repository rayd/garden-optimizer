# Fly.io Secrets and Configuration

This file documents all the environment variables and secrets needed for Garden Optimizer on fly.io.

## Required Secrets

Set these with: `flyctl secrets set VARIABLE_NAME="value"`

### `DATABASE_URL` (Required)
PostgreSQL connection string from Neon.

**Format:**
```
postgresql://user:password@host/database?sslmode=require
```

**Where to get it:**
1. Log into https://console.neon.tech
2. Select your project
3. Click "Connection String" or "Pooled Connection"
4. Copy the full connection string
5. Copy everything including `?sslmode=require`

**Example:**
```bash
flyctl secrets set DATABASE_URL="postgresql://neon_user:abc123@ep-xxxx.us-east-1.neon.tech/neondb?sslmode=require"
```

### `SECRET_KEY_BASE` (Required)
Phoenix session encryption key. Generate with: `mix phx.gen.secret`

**Example:**
```bash
flyctl secrets set SECRET_KEY_BASE="aBcDeF123456789..."
```

### `PHX_HOST` (Required)
Your app's domain name.

**Format:**
```
your-app-name.fly.dev
```

**Example:**
```bash
flyctl secrets set PHX_HOST="garden-optimizer.fly.dev"
```

## Optional Secrets

### `ANTHROPIC_API_KEY`
Claude API key for importing plants from URLs.

**Where to get it:** https://console.anthropic.com/account/keys

**Example:**
```bash
flyctl secrets set ANTHROPIC_API_KEY="sk-ant-..."
```

### `ACCESS_CODE`
Optional: Protect the app with an access code.
- If set, users must visit `/?access=CODE` first
- Without this, the site is completely open

**Example:**
```bash
flyctl secrets set ACCESS_CODE="my-secret-code"
```

## Configuration Variables (Environment)

These are set in `fly.toml` and can be overridden with `flyctl secrets set`:

### `LOG_LEVEL`
Default: `info`
- `debug`: Verbose logging
- `info`: Standard logs
- `warn`: Only warnings
- `error`: Only errors

### `POOL_SIZE`
Default: `10`
Number of database connections in the pool.
- For free tier: keep at 10-15
- For production: may increase to 20-30

## Full Deployment Command

After setting all required secrets:

```bash
flyctl secrets set \
  DATABASE_URL="postgresql://..." \
  SECRET_KEY_BASE="..." \
  PHX_HOST="garden-optimizer.fly.dev"
```

Then deploy:
```bash
flyctl deploy
```

## Verifying Secrets

List all set secrets (values are hidden):
```bash
flyctl secrets list
```

## Changing Secrets

To update a secret:
```bash
flyctl secrets set VARIABLE_NAME="new_value"
```

The app will automatically restart with the new value.

## Using Secrets from a .env File

If you have a `.env` file locally, extract values and set them:

```bash
# Option 1: Manually set each one
flyctl secrets set DATABASE_URL="..."
flyctl secrets set SECRET_KEY_BASE="..."

# Option 2: Read from dotenv (requires jq)
export $(cat .env.production | xargs) && flyctl secrets set \
  DATABASE_URL="$DATABASE_URL" \
  SECRET_KEY_BASE="$SECRET_KEY_BASE"
```

## Troubleshooting Secrets

### App won't start with "DATABASE_URL missing" error
- Verify the secret is set: `flyctl secrets list`
- Check it's correct in Neon console
- Ensure connection string includes `?sslmode=require`

### Cookies/sessions not working
- Check `SECRET_KEY_BASE` is set and consistent
- Generate a new one if unsure: `mix phx.gen.secret`
- Update with `flyctl secrets set`

### CSRF token errors
- Usually caused by `PHX_HOST` mismatch
- Verify it matches your actual domain
- Update with `flyctl secrets set PHX_HOST="your-domain"`

## Secrets Rotation

To rotate `SECRET_KEY_BASE` without losing user sessions:
1. Keep current value, note it down
2. Generate new value: `mix phx.gen.secret`
3. Update secret: `flyctl secrets set SECRET_KEY_BASE="new_value"`
4. Existing sessions will be invalidated (users will need to log back in if applicable)

## Protecting Secrets

- Never commit secrets to git
- Keep your Fly.io API token safe
- Use different secrets for staging vs production
- Rotate secrets periodically

## Additional Help

- View app logs: `flyctl logs`
- SSH into app: `flyctl ssh console`
- Check configuration: `flyctl config show`
