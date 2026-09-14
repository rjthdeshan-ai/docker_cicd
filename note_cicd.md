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

---

## Where we are now

- CI runs tests directly on GitHub's runner (`pytest -v`), **not** through
  Docker yet. The `Dockerfile` exists but `ci.yml` doesn't use it.

## What's next (not done yet)

- [ ] **Wire the Dockerfile into CI** — change `ci.yml` so it does
      `docker build` + `docker run` instead of installing pytest directly
      on the runner. This proves "tests pass in the exact same container
      we'd ship," not just "tests pass on GitHub's machine."
- [ ] **Learn CD (Continuous Deployment)** — e.g., push the built Docker
      image to a registry (Docker Hub / GHCR) automatically when tests pass.
