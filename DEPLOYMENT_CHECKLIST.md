# Garden Optimizer - Deployment Checklist

Follow this checklist to deploy Garden Optimizer to fly.io with Neon PostgreSQL.

## Pre-Deployment Setup

- [ ] Have a Fly.io account (https://fly.io)
- [ ] Have Flyctl CLI installed locally
- [ ] Have a Neon account (https://neon.tech)
- [ ] Have a GitHub account (optional, for CI/CD)
- [ ] Local clone of garden-optimizer repo with latest code

## Step 1: Prepare Secrets Locally

Generate required secrets before deployment. Do this locally and save them securely.

- [ ] Generate `SECRET_KEY_BASE`:
  ```bash
  mix phx.gen.secret
  ```
  Save the output (64+ character string)

- [ ] Set up Neon database:
  1. [ ] Go to https://console.neon.tech
  2. [ ] Create a new project
  3. [ ] Create a database (or use default `neondb`)
  4. [ ] Copy the connection string
  5. [ ] Verify it looks like: `postgresql://user:password@host/database?sslmode=require`
  6. [ ] Save the connection string

- [ ] Prepare optional secrets:
  - [ ] ANTHROPIC_API_KEY (from https://console.anthropic.com)
  - [ ] ACCESS_CODE (for gating the site, optional)

## Step 2: Create Fly App

- [ ] Create the Fly app:
  ```bash
  flyctl apps create garden-optimizer
  ```
  (Use a different name if `garden-optimizer` is taken)

- [ ] Update `fly.toml` if you used a different app name:
  ```toml
  app = "your-chosen-name"
  ```

## Step 3: Set Environment Variables

Set secrets on Fly.io (replace with your actual values):

```bash
flyctl secrets set \
  DATABASE_URL="postgresql://user:password@host/database?sslmode=require" \
  SECRET_KEY_BASE="your-64-char-secret-here" \
  PHX_HOST="your-app-name.fly.dev"
```

Optional:
```bash
flyctl secrets set \
  ANTHROPIC_API_KEY="sk-ant-..." \
  ACCESS_CODE="your-code"
```

Checklist:
- [ ] `DATABASE_URL` set (from Neon)
- [ ] `SECRET_KEY_BASE` set (generated locally)
- [ ] `PHX_HOST` set (your fly.dev domain)
- [ ] `ANTHROPIC_API_KEY` set (if using plant import)
- [ ] `ACCESS_CODE` set (if protecting the site)

## Step 4: Deploy the App

- [ ] Commit all changes to git:
  ```bash
  git add -A
  git commit -m "Deploy config for fly.io with Neon"
  ```

- [ ] Deploy to Fly.io:
  ```bash
  flyctl deploy
  ```

- [ ] Watch the deployment:
  - Takes 3-5 minutes typically
  - Watch logs: `flyctl logs`

- [ ] Check app status:
  ```bash
  flyctl status
  ```
  Should show: `Running` (green)

## Step 5: Verify Database Setup

Migrations should run automatically on first deploy.

To manually run migrations if needed:
```bash
flyctl ssh console
# Inside the console:
./bin/garden_optimizer eval "GardenOptimizer.Release.migrate"
```

- [ ] SSH into app and verify DB is working:
  ```bash
  flyctl ssh console
  # Inside console:
  ./bin/garden_optimizer eval "GardenOptimizer.Repo.query!('SELECT 1')"
  ```
  Should return success (no errors)

## Step 6: Seed Database (Optional)

Add sample data to the database:

```bash
flyctl ssh console
# Inside console:
./bin/garden_optimizer eval "GardenOptimizer.Release.seed"
```

- [ ] Database seeded with sample data (or skipped)

## Step 7: Test the App

- [ ] Open the app:
  ```bash
  flyctl open
  ```

- [ ] [ ] App loads without errors
- [ ] [ ] Pages render correctly
- [ ] [ ] Database operations work (create/read/update a garden)
- [ ] [ ] If using plant import, test with an API key

## Step 8: Set Up CI/CD (Optional)

For automatic deployments on git push:

- [ ] Create GitHub repository (if not already)
- [ ] Push code to GitHub:
  ```bash
  git remote add origin https://github.com/yourusername/garden-optimizer.git
  git branch -M main
  git push -u origin main
  ```

- [ ] Set GitHub Actions secret:
  1. [ ] Go to repo Settings → Secrets and variables → Actions
  2. [ ] Click "New repository secret"
  3. [ ] Name: `FLY_API_TOKEN`
  4. [ ] Get token from: `flyctl auth token`
  5. [ ] Paste and save

- [ ] `.github/workflows/deploy.yml` is already in place
- [ ] Test by pushing a commit to main:
  ```bash
  git commit --allow-empty -m "Test CI/CD"
  git push
  ```

## Step 9: Monitoring

Set up alerts and monitoring:

- [ ] Check logs regularly:
  ```bash
  flyctl logs -n 100
  ```

- [ ] Monitor app status:
  ```bash
  flyctl status
  ```

- [ ] Set up Neon alerts (optional):
  1. Go to https://console.neon.tech
  2. Select project → Settings → Alerts
  3. Set email alerts for connection errors

## Step 10: Documentation

- [ ] Share access instructions with users:
  - App URL: `https://your-app-name.fly.dev`
  - Access code (if set): `your-code`

- [ ] Document your deployment:
  - [ ] Save app name
  - [ ] Save Neon project name
  - [ ] Save Fly API token location
  - [ ] Document any custom modifications

## Maintenance Tasks

### Regular Backups

Neon handles automatic backups. To verify:
- [ ] Log into https://console.neon.tech
- [ ] Select project → Backups
- [ ] Verify recent automatic backups exist

### Database Cleanup

Periodically clean up test data:
```bash
flyctl ssh console
# Run Elixir code to delete test gardens
```

### Update Dependencies

Periodically update dependencies and redeploy:
```bash
mix deps.update --all
git commit -am "Update dependencies"
git push
```

(CI/CD will auto-deploy if set up)

## Troubleshooting Checklist

If deployment fails:

- [ ] Check logs: `flyctl logs -n 50`
- [ ] Verify secrets are set: `flyctl secrets list`
- [ ] Check DATABASE_URL format (should end with `?sslmode=require`)
- [ ] Verify PHX_HOST matches your domain
- [ ] Check Neon status at https://status.neon.tech

If the app starts but pages fail:

- [ ] Ensure SECRET_KEY_BASE is set
- [ ] Verify PHX_HOST is correct
- [ ] Run migrations: `flyctl ssh console` then `./bin/garden_optimizer eval "GardenOptimizer.Release.migrate"`

## Rollback Procedure

If you need to revert to a previous deployment:

```bash
# View recent deployment history
flyctl releases

# Rollback to previous version
flyctl releases rollback <version-number>
```

## Cleanup (If Removing)

To delete the deployment:

```bash
# Delete from Fly.io (app stays in Neon)
flyctl apps destroy garden-optimizer

# Also delete from Neon (go to https://console.neon.tech)
# Select project → Settings → Delete Project
```

## Success Criteria

Deployment is complete when:

- ✅ `flyctl status` shows "Running"
- ✅ `flyctl open` loads the app without errors
- ✅ Database operations work (gardens can be created/viewed)
- ✅ Logs show no critical errors: `flyctl logs`
- ✅ Optional: Plant import works if using ANTHROPIC_API_KEY

## Next Steps

After successful deployment:

1. Monitor logs for errors
2. Share app URL with users
3. Set up regular maintenance backups
4. Plan for scaling if traffic increases
5. Set up monitoring/alerts on Fly.io

## Support

- Fly.io Docs: https://fly.io/docs
- Phoenix Deployment: https://hexdocs.pm/phoenix/deployment.html
- Neon Docs: https://neon.tech/docs
- This project: See README.md and DEPLOYMENT.md
