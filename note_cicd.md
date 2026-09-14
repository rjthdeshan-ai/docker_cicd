# CI/CD Learning Notes (docker_cicd practice repo)

Running notes on what we've done, in plain language. Updated after each step.

---

## The project

A tiny toy app used only to practice Docker + CI/CD, separate from the real
KMC_Automation project.

- `app.py` — one function: `add(a, b)` returns `a + b`
- `test_app.py` — one test: checks `add(2, 3) == 5`
- `Dockerfile` — packages the app + pytest into a container image
- `.github/workflows/ci.yml` — tells GitHub Actions what to run automatically

---

## Step 1: Get the app running in Docker (done earlier)

Built the image and ran the container to prove pytest runs inside Docker,
not just on the host machine.

## Step 2: Add GitHub Actions CI (commit `641ea5b`)

Created `.github/workflows/ci.yml`. Every time we `git push`, GitHub:
1. Spins up a fresh Ubuntu machine ("runner")
2. Checks out our code
3. Installs Python 3.12
4. Runs `pip install pytest`
5. Runs `pytest -v`

If the tests pass → green checkmark on the Actions tab.
If any test fails → red X, and the pipeline is marked "failed."

This is the core idea of **CI (Continuous Integration)**: tests run
automatically on every push, with no human needing to remember to run them.

## Step 3: Prove CI actually catches bugs (commits `431cc41` → `5543ead`)

We deliberately broke the test to see CI fail, then fixed it, to see the
full cycle:

1. Changed the test to assert `add(2, 3) == 6` (wrong — the real answer is 5)
2. Ran pytest locally → it failed, as expected:
   `FAILED test_app.py::test_add - assert 5 == 6`
3. Committed + pushed (`431cc41` — "Break test_add on purpose to see CI catch it")
4. Checked the GitHub Actions tab → **red fail mark**, confirmed by you
5. Reverted the test back to `add(2, 3) == 5`
6. Committed + pushed (`5543ead` — "Fix test_add back to correct assertion")
7. CI re-ran automatically → back to green

**Takeaway:** CI isn't just "a green badge that always passes." It's a
tripwire — if someone pushes broken code, CI turns red immediately and
everyone can see it, before it ever reaches production. In a real team,
a red CI run typically blocks merging a pull request.

## Step 4: Wire the Dockerfile into CI (commit `5e14572`)

Changed `ci.yml` so it no longer installs Python/pytest directly on the
GitHub runner. Instead it now does the same two steps you'd do on your own
machine:

```yaml
- name: Build Docker image
  run: docker build -t docker_cicd .

- name: Run tests inside Docker container
  run: docker run docker_cicd
```

Removed the old `actions/setup-python@v5` step — it's no longer needed
because Docker brings its own Python (from `Dockerfile`'s
`FROM python:3.12-slim`), so the runner doesn't need Python installed
separately.

**Why this matters:** before, CI was proving "the code passes tests on
GitHub's bare Ubuntu machine." Now CI proves "the actual container we would
ship passes tests." Those aren't always the same thing — the Dockerfile
could theoretically use a different Python version, different OS packages,
etc. than the raw runner. Building through Docker in CI closes that gap.

---

## Where we are now

- CI builds the Docker image and runs the container on every push. The
  `Dockerfile` is now the source of truth for both local testing and CI.
- We have **CI** (Continuous Integration — tests run automatically) but
  no **CD** (Continuous Deployment) yet — a passing build doesn't publish
  or deploy anything anywhere.

## Step 5: Add CD — push image to GHCR (commit `56ca026`)

Added two steps to `ci.yml`, after the tests pass:

```yaml
- name: Log in to GitHub Container Registry
  if: github.ref == 'refs/heads/main'
  run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

- name: Tag and push image to GHCR
  if: github.ref == 'refs/heads/main'
  run: |
    docker tag docker_cicd ghcr.io/${{ github.repository_owner }}/docker_cicd:latest
    docker push ghcr.io/${{ github.repository_owner }}/docker_cicd:latest
```

Also added `permissions: packages: write` to the job, so the automatic
`GITHUB_TOKEN` is allowed to publish packages/images.

**How it works:**
- `GITHUB_TOKEN` is auto-generated per run by GitHub Actions — no secrets
  to create manually.
- The `if: github.ref == 'refs/heads/main'` guard means images are only
  published from the `main` branch, not from every PR/branch.
- These steps run *after* "Run tests inside Docker container" — if tests
  fail, the job stops and nothing gets pushed. That's the actual CI → CD
  link: only tested, working images get published.
- Result: on every push to `main` with passing tests, a fresh image lands
  at `ghcr.io/<owner>/docker_cicd:latest`, ready to `docker pull`.

**Confirmed:** CI #6 (commit `56ca026`) ran green — build, test, GHCR
login, and image push all succeeded.

## Step 6: Tag images by commit SHA, not just `:latest` (commit pending)

Updated the "Tag and push image to GHCR" step in `ci.yml`:

```yaml
- name: Tag and push image to GHCR
  if: github.ref == 'refs/heads/main'
  run: |
    SHORT_SHA=$(echo "${{ github.sha }}" | cut -c1-7)
    docker tag docker_cicd ghcr.io/${{ github.repository_owner }}/docker_cicd:latest
    docker tag docker_cicd ghcr.io/${{ github.repository_owner }}/docker_cicd:$SHORT_SHA
    docker push ghcr.io/${{ github.repository_owner }}/docker_cicd:latest
    docker push ghcr.io/${{ github.repository_owner }}/docker_cicd:$SHORT_SHA
```

**Why:** before, every push overwrote `:latest` with nothing to fall back
to. `github.sha` is a built-in variable — the full 40-character commit hash
of whatever commit triggered the run — and `cut -c1-7` shortens it to match
the short hashes already used in this file (e.g. `56ca026`). Now every push
to `main` publishes **two** tags: `:latest` (always newest) and a permanent
`:<short-sha>` tag that's never overwritten. If a future deploy breaks, you
can roll back to any exact past build by its commit SHA instead of only
ever having whatever `latest` currently points to.

**Confirmed:** CI #8 (commit `ff05282`) ran green — the SHA-tagging step
worked, publishing both `:latest` and `:ff05282` to GHCR.

## Step 7: Simulated Deploy — auto-pull and run the published image (commit pending)

Added a second job, `deploy`, to `ci.yml`:

```yaml
  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read
    steps:
      - name: Log in to GitHub Container Registry
        run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

      - name: Pull published image from GHCR
        run: docker pull ghcr.io/${{ github.repository_owner }}/docker_cicd:latest

      - name: Run the published image (simulated deploy)
        run: docker run ghcr.io/${{ github.repository_owner }}/docker_cicd:latest
```

**Why this matters / what it teaches:**
- `needs: test` — new keyword. Forces `deploy` to wait until `test`
  (build + test + publish) finishes successfully before it starts. Jobs
  run in parallel by default, so without `needs:` this could try to pull
  an image before it's published.
- Each **job** gets its own fresh virtual machine — nothing is shared
  between `test` and `deploy`, not even the locally-built image. That's
  why `deploy` has to `docker login` again, and why it only does
  `docker pull` + `docker run` — never `docker build`. This forces it to
  prove the *published* artifact works, not just whatever was cached
  locally in the previous job.
- Result: every push to `main` now does the full loop automatically —
  build → test → publish → **pull the published image back down and run
  it** — with no manual steps, entirely on free GitHub infrastructure.
  This is the real "CD" (Continuous **Deployment**), not just delivery.

**Confirmed:** CI #9 (commit `8ef5c80`) ran green — both the `test` job
(build, test, publish) and the new `deploy` job (pull, run) succeeded, in
order. Full build → test → publish → pull → run loop confirmed working,
fully automated, on every push to `main`.

## What's next (not done yet)

- [ ] (Further out, real infra) Deploy to an actual server or platform
      (e.g. a VM or Render/Fly.io) instead of simulating it inside GitHub
      Actions.
- [ ] (Further out, real workflow) Practice a PR-based workflow: push to
      a feature branch, open a pull request, watch CI run on the PR
      *before* merging, then merge to `main` to trigger CD — closer to
      how a real team works than pushing straight to `main`.
- [ ] Once comfortable with the above, consider applying these same
      CI/CD patterns to `KMC_Automation` — only when explicitly decided,
      since that's a real system with real UAT billing data.

---

## Where we are now (updated)

Full CI/CD loop is working end-to-end for this toy app:
push to `main` → Docker image built → tests run inside the container →
on success, image is tagged and published to GHCR. This is the same
pattern a real project would use before adding an actual deployment step.

## End goal of this practice repo

Not to ship this toy app anywhere real — it's to practice the full loop
that a real project (like `KMC_Automation`) would use:

1. **CI**: every push automatically builds the Docker image and runs tests
   inside it → catches breakage immediately (done ✅)
2. **CD**: on a green build, automatically push the image to a container
   registry (e.g. GHCR — GitHub Container Registry, free and built in) with
   a version tag → produces a deployable artifact without manual steps
   (not done yet)
3. (Optional, further out) **Deploy**: something pulls that tagged image
   and runs it somewhere (a server, a cloud service) — the actual "ship it"
   step

Once you're comfortable with steps 1–2 here, in `docker_cicd`, the same
pattern can later be applied to `KMC_Automation` — but only when you
explicitly decide to, since that's a real system with real UAT billing
data and deserves extra care.
