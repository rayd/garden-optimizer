# Garden Optimizer - Fly.io Deployment Setup

This directory now contains everything needed to deploy Garden Optimizer to fly.io with Neon PostgreSQL.

## What's Been Added

### Deployment Files

1. **fly.toml** - Fly.io application configuration
   - App name, region, machine specs, health checks
   - Build configuration for Elixir 1.20 / OTP 29
   - Already uses the correct versions for your project

2. **Dockerfile** - Docker build configuration
   - Multi-stage build for minimal image size
   - Compiles Elixir, Phoenix assets (Tailwind + esbuild)
   - Uses debian-bookworm-slim for runtime

3. **docker-entrypoint.sh** - Container startup script
   - Handles migrations and database seeding
   - Ensures app starts correctly on fly.io

4. **.dockerignore** - Excludes unnecessary files from Docker image
   - Keeps image size small

### Release Module

5. **lib/garden_optimizer/release.ex** - New Elixir module
   - Provides `migrate()` and `seed()` functions
   - Called by the entrypoint script
   - Enables running migrations in production

### Documentation

6. **DEPLOYMENT.md** - Complete deployment guide
   - Step-by-step instructions
   - Neon setup walkthrough
   - Environment variable explanation
   - Troubleshooting guide

7. **FLY_SECRETS.md** - Secrets and environment variable reference
   - Details on each required/optional secret
   - Where to get connection strings
   - How to rotate secrets
   - Troubleshooting secrets issues

8. **DEPLOYMENT_CHECKLIST.md** - Interactive checklist
   - Pre-deployment verification
   - Step-by-step deployment process
   - Post-deployment testing
   - Maintenance tasks

### CI/CD (Optional)

9. **.github/workflows/deploy.yml** - GitHub Actions workflow
   - Automatically deploys when you push to main
   - Only needed if using GitHub

## Quick Start

### 1. Generate Secret Key

```bash
mix phx.gen.secret
```
Save the output.

### 2. Set Up Neon Database

1. Go to https://console.neon.tech
2. Create a new project
3. Copy the connection string

### 3. Create Fly App

```bash
flyctl apps create garden-optimizer
```

### 4. Set Secrets

```bash
flyctl secrets set \
  DATABASE_URL="postgresql://..." \
  SECRET_KEY_BASE="..." \
  PHX_HOST="garden-optimizer.fly.dev"
```

### 5. Deploy

```bash
flyctl deploy
```

That's it! The app will be running at `https://garden-optimizer.fly.dev`

## Detailed Instructions

For step-by-step walkthrough, see **DEPLOYMENT.md**.

For a checklist version, see **DEPLOYMENT_CHECKLIST.md**.

For secrets details, see **FLY_SECRETS.md**.

## What Changed in the Repo

- ✅ No changes to existing source code
- ✅ No changes to dependencies
- ✅ Added 1 new Elixir module (Release)
- ✅ Added 4 deployment configuration files
- ✅ Added 3 documentation files
- ✅ Added optional GitHub Actions workflow

Everything is backwards compatible with local development.

## Local Development

Nothing changes for local development:

```bash
export ANTHROPIC_API_KEY=sk-...
mix setup
mix phx.server
```

## Environment Variables Explained

### Required
- **DATABASE_URL**: Neon PostgreSQL connection string
- **SECRET_KEY_BASE**: Phoenix session encryption key (generated)
- **PHX_HOST**: Your fly.dev domain (e.g., garden-optimizer.fly.dev)

### Optional
- **ANTHROPIC_API_KEY**: Claude API key for plant importing
- **ACCESS_CODE**: Gate the site with an access code

### Defaults (in fly.toml)
- **LOG_LEVEL**: "info"
- **POOL_SIZE**: "10" (database connections)
- **PORT**: "4000"

## After Deployment

1. ✅ Verify app loads: `flyctl open`
2. ✅ Check status: `flyctl status`
3. ✅ Watch logs: `flyctl logs`
4. ✅ Test database operations

## Key Files to Review

1. **fly.toml** - High-level app configuration
2. **Dockerfile** - Docker build process
3. **DEPLOYMENT.md** - Full deployment guide

## Scaling

Default config:
- 1 shared CPU
- 256 MB RAM
- 1 machine (auto-scales from 0-3 by default)

To scale:
```bash
flyctl scale count 2          # Run 2 instances
flyctl scale memory 512       # 512 MB RAM per instance
```

## Costs

- **Fly.io**: Free tier includes 3 shared-cpu-1x 256MB VMs
- **Neon**: Free tier includes 3 projects, 5GB storage
- **Total**: Can run for free with monitoring

## Support Resources

- Fly.io Docs: https://fly.io/docs
- Neon Docs: https://neon.tech/docs
- Phoenix Deployment: https://hexdocs.pm/phoenix/deployment.html
- Elixir Releases: https://hexdocs.pm/mix/Mix.Tasks.Release.html

## Common Tasks

### View Logs
```bash
flyctl logs -n 100
```

### SSH into App
```bash
flyctl ssh console
```

### Update an Environment Variable
```bash
flyctl secrets set VARIABLE="new_value"
```

### Redeploy
```bash
git add .
git commit -m "Your changes"
flyctl deploy
```

### Check Database Connection
```bash
flyctl ssh console
# Inside console:
./bin/garden_optimizer eval "GardenOptimizer.Repo.query!('SELECT 1')"
```

### Run Migrations
```bash
flyctl ssh console
# Inside console:
./bin/garden_optimizer eval "GardenOptimizer.Release.migrate"
```

### Seed Database
```bash
flyctl ssh console
# Inside console:
./bin/garden_optimizer eval "GardenOptimizer.Release.seed"
```

## Files Structure

```
project-root/
├── fly.toml                          # Fly.io config
├── Dockerfile                        # Docker build
├── docker-entrypoint.sh              # Container startup
├── .dockerignore                     # Docker exclusions
├── DEPLOYMENT.md                     # Full guide
├── DEPLOYMENT_CHECKLIST.md           # Interactive checklist
├── DEPLOYMENT_README.md              # This file
├── FLY_SECRETS.md                    # Secrets reference
├── lib/
│   └── garden_optimizer/
│       └── release.ex                # NEW: Release module
├── .github/
│   └── workflows/
│       └── deploy.yml                # GitHub Actions (optional)
└── (rest of project unchanged)
```

## Next Steps

1. **Read DEPLOYMENT.md** for full instructions
2. **Read FLY_SECRETS.md** to understand environment variables
3. **Follow DEPLOYMENT_CHECKLIST.md** to deploy step-by-step
4. Monitor with `flyctl logs` and `flyctl status`

## Questions?

Refer to the appropriate documentation:
- "How do I deploy?" → **DEPLOYMENT.md**
- "What secrets do I need?" → **FLY_SECRETS.md**
- "I'm ready to deploy" → **DEPLOYMENT_CHECKLIST.md**
- "My app won't start" → See Troubleshooting in **DEPLOYMENT.md**

Good luck! 🚀
