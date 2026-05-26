# Contributing to PowerUserMail

## Branch Strategy

We use a simple Git flow:

```
dev (development) → main (releases)
```

### Branches

- **`main`** - Production branch. Only accepts merges from `dev` via PRs. Each merge creates an automatic release.
- **`dev`** - Development branch. All feature work happens here or in feature branches merged into `dev`.

### Workflow

1. **Daily development** happens on `dev` branch
2. **Feature branches** (optional): Create from `dev`, merge back to `dev`
3. **Releases**: Create a PR from `dev` → `main`
4. When PR is merged to `main`, a release is automatically created with:
   - A version tag (e.g., `v2024.12.03-123`)
   - A changelog of commits since last release
   - A downloadable `.zip` of the app

## CI/CD Pipeline

### On `dev` branch push:
- ✅ Build verification
- ✅ Run tests

### On PR to `main`:
- ✅ Build verification
- ✅ Run tests
- ⏳ Require review approval

### On merge to `main`:
- 🏗️ Build release version
- 📦 Create app archive
- 🏷️ Tag with version

## Support development

If PowerUserMail saves you time, tips fund releases and bugfixes:

- [Buy Me a Coffee](https://buymeacoffee.com/isaaclins)
- 🚀 Publish GitHub Release

## Quick Commands

```bash
# Switch to dev for development
git checkout dev

# Create a feature branch
git checkout -b feature/my-feature

# Merge feature to dev
git checkout dev
git merge feature/my-feature
git push

# Create a release (via GitHub PR)
# Go to GitHub → Pull Requests → New PR → base: main, compare: dev
```

## Setting Up Branch Protection (Recommended)

Go to GitHub → Settings → Branches → Add rule:

### For `main`:
- ✅ Require a pull request before merging
- ✅ Require status checks to pass (select "Build & Test")
- ✅ Require branches to be up to date

### For `dev`:
- ✅ Require status checks to pass (select "Build & Test")

