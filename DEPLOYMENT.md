# Garden Optimizer - Fly.io Deployment Guide

This guide walks you through deploying Garden Optimizer to fly.io using Neon (free tier PostgreSQL).

## Prerequisites

1. **Fly.io Account**: Sign up at https://fly.io
2. **Flyctl CLI**: Install from https://fly.io/docs/getting-started/installing-flyctl/
3. **Neon Account**: Sign up at https://neon.tech
4. **Git**: Ensure you have git installed
5. **Elixir/OTP**: The app runs on Elixir 1.20.4 with OTP 29 (Docker handles this automatically)

## Step 1: Generate Required Secrets

Before deploying, generate the `SECRET_KEY_BASE` that Phoenix needs:

```bash
mix phx.gen.secret
```

Copy the output — you'll need it in Step 4.

## Step 2: Set Up Neon Database

1. Go to https://console.neon.tech
2. Create a new project
3. Create a new database (or use the default `neondb`)
4. Copy the connection string — it will look like:
   ```
   postgresql://user:password@host/database?sslmode=require
   ```
5. Save this string for Step 4

## Step 3: Create Fly App

From the project root directory:

```bash
flyctl apps create garden-optimizer
```

If the name is taken, choose another and update `fly.toml` accordingly.

## Step 4: Set Environment Variables

Set the required secrets on fly.io. Replace `YOUR_SECRET_KEY_BASE` and `YOUR_DATABASE_URL`:

```bash
flyctl secrets set \
  DATABASE_URL="YOUR_DATABASE_URL" \
  SECRET_KEY_BASE="YOUR_SECRET_KEY_BASE" \
  PHX_HOST="your-app-name.fly.dev" \
  ANTHROPIC_API_KEY="sk-..." \
  ACCESS_CODE="optional-access-code"
```

### Environment Variables Explained

- **DATABASE_URL**: PostgreSQL connection string from Neon
  - Example: `postgresql://user:password@host/neondb?sslmode=require`
- **SECRET_KEY_BASE**: Phoenix session/cookie encryption key (from Step 1)
- **PHX_HOST**: Your app's domain (replace with your actual fly.dev domain)
- **ANTHROPIC_API_KEY**: Claude API key for plant importing (optional)
- **ACCESS_CODE**: Optional access token to protect the app

## Step 5: Deploy

```bash
flyctl deploy
```

This will:
1. Build the Docker image
2. Push it to fly.io's registry
3. Deploy the app
4. Run database migrations

## Step 6: Run Migrations and Seeds (First Deploy Only)

After the first deployment, run migrations if they didn't run automatically:

```bash
flyctl ssh console
# Inside the console:
./bin/garden_optimizer eval "GardenOptimizer.Release.migrate"
```

To seed the database with sample data:

```bash
flyctl ssh console
# Inside the console:
./bin/garden_optimizer eval "GardenOptimizer.Release.seed"
```

## Step 7: Access Your App

Open your app:

```bash
flyctl open
```

Your app should now be running at `https://your-app-name.fly.dev`

## Monitoring and Logs

View logs:
```bash
flyctl logs
```

Monitor app status:
```bash
flyctl status
```

SSH into the app:
```bash
flyctl ssh console
```

## Updating Environment Variables

To update secrets without redeploying:

```bash
flyctl secrets set VARIABLE_NAME="new_value"
```

To view current secrets (values are hidden):
```bash
flyctl secrets list
```

## Scaling

The default configuration in `fly.toml` runs:
- 1 shared CPU
- 256 MB RAM
- 1 machine

To scale:
```bash
flyctl scale count 2          # Run 2 instances
flyctl scale vm shared-cpu-1  # Change instance type
flyctl scale memory 512       # Increase to 512 MB RAM
```

## Troubleshooting

### App won't start
Check logs:
```bash
flyctl logs --detailed
```

### Database connection errors
1. Verify `DATABASE_URL` is set correctly
2. Check Neon console for active databases
3. Ensure Neon connection is not in suspended state

### Assets not loading (CSS/JavaScript broken)
Make sure `PHX_HOST` is set correctly and matches your actual domain.

### Out of memory
Increase RAM in `fly.toml` or Scale via flyctl.

## Neon Free Tier Limits

- 3 projects
- 5 GB storage
- Automatic suspend after 7 days of inactivity
- Up to 20 connections

For more details, see https://neon.tech/pricing

## Database Backups

Neon handles backups automatically. To access backups:
1. Log into Neon console
2. Navigate to your project's "Backups" tab
3. Restore from a backup point in time if needed

## Updating Your App

To redeploy after code changes:

```bash
git add .
git commit -m "Your commit message"
flyctl deploy
```

If you made database schema changes, migrations run automatically on deploy.

## Removing the App

To delete the fly.io app (keeps Neon database intact):

```bash
flyctl apps destroy garden-optimizer
```

To also delete the Neon database, go to https://console.neon.tech and delete the project.

## Maintaining Base Images

The Dockerfile currently uses:
- **Builder**: Elixir 1.20 with OTP 29 on Debian Trixie
- **Runtime**: Debian Trixie Slim (current stable as of 2025)

To keep your deployment secure:

1. **Monitor Debian releases** at https://www.debian.org/releases/
2. **Check hex.pm** for available Elixir image tags: https://hub.docker.com/r/hexpm/elixir/tags
3. **When a new Debian stable releases**, update both:
   - `hex.pm/elixir:1.20-erlang-29-debian-<new-version>`
   - `debian:<new-version>-slim`
4. **Rebuild and deploy**:
   ```bash
   # Update Dockerfile with new Debian version
   flyctl deploy --no-cache
   ```

Current Debian versions:
- **Trixie** (13) — Current stable (2025+)
- **Bookworm** (12) — Previous stable
- **Bullseye** (11) — Older stable

## Additional Resources

- [Fly.io Documentation](https://fly.io/docs/)
- [Phoenix Deployment Guides](https://hexdocs.pm/phoenix/deployment.html)
- [Neon Documentation](https://neon.tech/docs)
- [Elixir Releases](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- [Debian Releases](https://www.debian.org/releases/)
- [hex.pm Elixir Images](https://hub.docker.com/r/hexpm/elixir/tags)
