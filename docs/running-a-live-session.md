# Running a live session

A practical runbook for hosting a live voting session in front of an audience, for example during a workshop or talk, where people join from their phones by scanning a QR code on the big screen.

For how the feature works internally, see [live-voting-sessions.md](live-voting-sessions.md).

## How it works in one line

The presenter view is shown on the big screen. It displays a QR code and a join link. The audience scans the QR, lands on the join page, and votes. The presenter advances the questions and everyone's screen follows, with the tally updating live.

## Deploy checklist (do this before the day)

The app must be on a publicly reachable domain over https so phones can open the join link.

- **Set `PHX_HOST` to your real domain.** The QR and the join link are built from the endpoint URL config (`config/runtime.exs`), which reads `PHX_HOST`. The fallback is `example.com`, so if `PHX_HOST` is unset the QR will point at the wrong place. This is the single most important setting.
- **Confirm WebSockets reach the app over that domain.** Everything live (the presence count and roster, the results updating, the question advancing) rides the LiveView socket. With `PHX_HOST` plus https, LiveView uses `wss://` and the default `check_origin` matches automatically. Behind a proxy or CDN, make sure it forwards the WebSocket upgrade and that the domain passes `check_origin`.
- **Set the rest of the release env** as usual (`SECRET_KEY_BASE`, the `DB_*` variables, and so on).
- **Dry run from a phone**, ideally on cellular rather than the venue wifi: open the deployed presenter, scan the QR, join, and cast a vote. Confirm the presenter screen updates without a reload. This exercises both the domain and the WebSocket in one go.

## Prepare the poll and session (as the owner)

1. Log in (magic link).
2. Create a poll and add its questions and options. For quiz style questions, toggle the **correct** option. The correct answer is revealed in the results, there is no scoring.
3. Create a **Voting** session on the poll. Turn **public** on so people can join as guests without logging in. A non-public session sends visitors to the login page instead.
4. The session starts in the **Pending** state, ready to present.

## During the session

1. Open the session in **Present** (the "Present" action on the poll, or `/sessions/:id/present`) and put it on the big screen.
2. The share card shows the **QR code** ("Scan to join") and the **join link** ("Or open the link"). The presence badge shows who is connected: you as the host, plus a count of guests.
3. The audience **scans the QR** (or types the link). For a public session they are in immediately as guests, no name and no access code needed.
4. Click **Start**. The first question appears on every screen.
5. People **vote**. It is single choice, and tapping another option changes their vote. The presenter shows the live tally: counts, percentages, and bars.
6. Use **Next** and **Previous** to move through the questions. Everyone's screen follows. The correct option, if any, is highlighted on the presenter.
7. Click **End** to close voting. Participants see that the session has ended.

## Good to know

- The QR and the link point at the same public join URL, derived from `PHX_HOST`.
- **No access code is required** to join in this version. The unguessable slug link (the QR) is the access mechanism. The code shown in the session form is not enforced.
- Votes are **anonymous and single choice**. A re-vote replaces the previous one. Results are aggregate counts; live tallies show on the presenter, and the final results are shown to participants after the session ends.
- In the presence roster, named people (you, and anyone logged in) appear as individual chips, while everyone else is summed up as "N guests". The "N here" count is the true number connected.
- To review the tally yourself, use the **Results** action on the poll's session list (`/sessions/:id/results`). It shows every question's result and updates live. This is also how you watch a **survey**, which has no presenter view, fill in.
- If you **End** a session and need to resume, **Reopen** it from the poll's session list. It returns to Active and people can rejoin with the same link.
- If a screen ever looks stale, a browser refresh re-syncs it, since the state is restored from the server.

## Day-of checklist

- [ ] `PHX_HOST` is the real domain, and https works
- [ ] A phone can open the join link and the presenter updates live (WebSocket reaches the app)
- [ ] The poll has questions and options, with correct answers toggled if it is a quiz
- [ ] The session is created, public, and currently Pending
- [ ] The Present view is open on the big screen with the QR visible
- [ ] Phone test passed: scan, join, vote, presenter updates
