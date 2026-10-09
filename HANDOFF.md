# Working on Amber

For anyone picking this up from Caleb. Everything here was true on 2026-09-27.

## Access you need

| What | Why | How you get it |
| --- | --- | --- |
| This repo | the code | done |
| Railway project `amber-circles` | deploy the server, read its env vars | Caleb invites you from the Railway dashboard |
| App Store Connect, team 4DMVHH99R2 | TestFlight, uploading builds | done (App Manager) |
| "Access to Certificates, Identifiers & Profiles" | signing builds on your own Mac | Caleb ticks it on your user in App Store Connect, Users and Access |
| An Anthropic API key | running the server locally | your own, or read it from Railway variables. Never paste keys into chat or commit them |

## Tools

```bash
brew install node postgresql@16 xcodegen railway
```

Plus Xcode 26 or later, signed in with your Apple ID (Xcode, Settings, Accounts).

## Run the server locally

```bash
npm install
createdb -p 5433 amber   # or point DATABASE_URL at any Postgres
DATABASE_URL=postgres://localhost:5433/amber AMBER_SECRET=anything-long ANTHROPIC_API_KEY=... PORT=8787 node server.js
AMBER_URL=http://localhost:8787 node --test test/*.test.js
```

The schema applies itself on boot. The iPhone app talks to production (`ios/Shared/API.swift`, `API.base`); point it at your Mac's address to test server changes before deploying.

## Deploy the server

```bash
railway link            # pick amber-circles
railway up --service web --detach
AMBER_URL=https://web-production-058309.up.railway.app npm test
```

Pushing to GitHub does not deploy. The tests clean up after themselves, so running them against production is fine.

## Build the iPhone app

```bash
cd ios
xcodegen generate                # after any change to project.yml
open AmberCircles.xcodeproj      # run the Amber scheme on a simulator, then open Messages
```

Never edit `Messages/Messages.entitlements` by hand: xcodegen rewrites it from `project.yml`. Builds 44 and 45 shipped without Sign in with Apple because of exactly that.

## Ship a TestFlight build

1. Bump `CURRENT_PROJECT_VERSION` in `ios/project.yml`, then `xcodegen generate`.
2. Archive and upload:

```bash
cd ios
xcodebuild -project AmberCircles.xcodeproj -scheme Amber -destination generic/platform=iOS \
  -archivePath /tmp/Amber.xcarchive archive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath /tmp/Amber.xcarchive -exportOptionsPlist export.plist \
  -exportPath /tmp/AmberExport -allowProvisioningUpdates
```

3. It processes in App Store Connect in about 10 to 15 minutes, then shows up for the "Origin Weekend" tester group.

## Where things live

- `ios/Messages/Views.swift`: every screen. `LivePanel.swift` is the preview, `Pins.swift` the pinned comments, `Voice.swift` hold-to-talk, `ChatStore.swift` all state and actions.
- `agent.js`: what Amber says and when it is allowed to build. `builder.js`: how apps get written and patched.
- `server.js` and `schema.sql`: the API and the database.

## Open items

- Sign in with Apple has not been confirmed on a real phone. "Continue without signing in" always works.
- Pinned comments were tested in a browser, not yet inside iMessage on a phone.
- The public TestFlight link (https://testflight.apple.com/join/7DMFRSv8) waits on Apple's beta review.

## TestFlight from the API (added 2026-10-09)

`tools/asc.py` signs App Store Connect API calls with the team key, so testers, groups and beta review need no browser. The app is `6765705839` ("Amber Keyboard" in App Store Connect, bundle `com.calebnewton.amber`). The external group "Try Amber" is `888a890d-dd58-4cab-b166-408b9c85b1fe` and owns the public link https://testflight.apple.com/join/7DMFRSv8.

- Invite someone: `POST /v1/betaTesters` with their Apple ID email and a `betaGroups` relationship to Try Amber. They get Apple's email.
- Ship a build to testers: `POST /v1/betaGroups/<group>/relationships/builds`, then `POST /v1/betaAppReviewSubmissions` for that build. Builds after the first approval have been approved within minutes.
- Internal groups (Origin Weekend) refuse a build POST with 422 because they get every build already.

Bump `CURRENT_PROJECT_VERSION` before every upload. A second upload of a build number that already exists still prints "Upload succeeded" and is then dropped by Apple without a word (build 62, 2026-10-09). Check the build list after uploading.

## Team board (added 2026-10-09)

`team.js` puts the Chewbacca team board (team/tasks on calebnewtonusc/Chewbacca) in a linked chat, and `team-check.js` asks Claude whether a finished task's commits actually do it. Railway vars: `TEAM_LINK_CODE`, `TEAM_GITHUB_TOKEN`, `TEAM_CHECK_REPOS`. Tests run only against a local server with `TEAM_LOCAL_DIR`, never production, because they write tasks. `claude-sonnet-5-5` refuses a forced `tool_choice`, so the check asks for its tool in the prompt instead.

Built with Chewbacca
