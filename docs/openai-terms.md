# Folio and OpenAI's terms

Researched November 10, 2026. **This is not legal advice.** It is a developer's reading of public documents. Anything marked as an open question needs a lawyer or a written answer from OpenAI.

## Sources and how they were read

openai.com returned HTTP 403 (a bot challenge) to direct fetches on November 10, 2026, so the OpenAI pages below were read from Wayback Machine snapshots taken between October 21 and November 9, 2026. The snapshot date is given for each. Quotes are verbatim from those snapshots.

| Document | Version | Snapshot read |
|---|---|---|
| [Terms of Use](https://openai.com/policies/terms-of-use/) (US) | Effective January 1, 2026 | [2026-11-09](https://web.archive.org/web/20261109200011/https://openai.com/policies/terms-of-use/) |
| [Terms of Use, rest of world](https://openai.com/policies/row-terms-of-use/) | Effective January 1, 2026 | [2026-09-02](https://web.archive.org/web/20260902130412/https://openai.com/policies/row-terms-of-use/). The November 6 snapshot only captured the bot challenge. The relevant clauses match the US text word for word. |
| [Europe Terms of Use](https://openai.com/policies/eu-terms-of-use/) (EEA, Switzerland, UK) | Updated January 16, 2026 | [2026-10-28](https://web.archive.org/web/20261028153406/https://openai.com/policies/eu-terms-of-use/) |
| [Usage Policies](https://openai.com/policies/usage-policies/) | Effective **November 20, 2026** (announced October 21, 2026) | [2026-11-06](https://web.archive.org/web/20261106200208/https://openai.com/policies/usage-policies/) |
| [Service Terms](https://openai.com/policies/service-terms/) | Updated October 16, 2026 | [2026-11-08](https://web.archive.org/web/20261108181350/https://openai.com/policies/service-terms/) |
| [Sign in with ChatGPT Terms](https://openai.com/policies/sign-in-with-chatgpt-terms/) | September 29, 2026 | [2026-10-21](https://web.archive.org/web/20261021154407/https://openai.com/policies/sign-in-with-chatgpt-terms/) |
| [Brand / Design Guidelines](https://openai.com/brand/) | Undated | [2026-10-21](https://web.archive.org/web/20261021174919/https://openai.com/brand/) |
| [Google OAuth 2.0 Policies](https://developers.google.com/identity/protocols/oauth2/policies) | Last modified August 5, 2026 | Fetched directly |
| [chatgpt.com/robots.txt](https://chatgpt.com/robots.txt) | Live | Fetched directly. It blocks named crawlers (CCBot, PerplexityBot and others) and has nothing on embedded browsers or clients. |

I found **no OpenAI page that speaks directly about third-party desktop wrappers or embedded browsers for chatgpt.com**. A search turned up only forum posts and blogs about account bans, which I did not treat as policy. The closest official signals are the "automatically or programmatically extract" clause in the Terms, the new model-access intermediary rule in the Usage Policies, and the Sign in with ChatGPT Terms. The last one does not bind Folio, because Folio doesn't use SIWC, but it shows plainly what OpenAI considers acceptable for third-party apps.

## 1. Summary verdict

Folio is in a **grey zone, but mostly low risk if a few changes are made**. Nothing in OpenAI's terms forbids viewing chatgpt.com in an embedded WebKit view. Every message is typed, approved and sent by the person, and it goes to their own account. That is the core of Folio's defence, and it should stay true.

The real exposure, in order:

1. **Session-cookie import from other browsers** is the one feature that looks bad on paper. OpenAI's own third-party app terms say "Do not ask users for their ChatGPT passwords or session cookies." Decrypting another browser's cookie store also looks like infostealer behaviour to security tools and to reviewers. This is the highest-risk feature, and it is optional.
2. **Branding.** "ChatGPT" in in-app labels that describe the feature is fine. It must stay out of the app name, icon, tagline and anything that suggests endorsement. A clear non-affiliation notice is expected, both by OpenAI's "Notifying users" guidance and by trademark law generally.
3. **Account risk falls on users, not on you.** Under the Terms the account holder "is responsible for all activities that occur under your account", and OpenAI may suspend accounts whose use "could cause risk or harm to OpenAI". If OpenAI decides embedded clients are abuse, users lose their accounts. Folio should say so plainly and avoid anything that looks like a bot.
4. **Practical fragility.** OpenAI can break Folio at any time (markup changes, bot checks, blocking WebKit views) without any legal step. It is not a compliance risk, but the product depends on OpenAI tolerating it.

## 2. Folio behaviours against the terms

The Terms clauses are the same in the US, rest-of-world and Europe versions unless noted. "ToU" below means all three.

| Folio behaviour | Relevant clause(s) | Risk | Why |
|---|---|---|---|
| Shows chatgpt.com in a `WKWebView`, and the person signs in themselves | ToU "What you can do": "Subject to your compliance with these Terms, you may access and use our Services." ToU applies to "any associated software applications and websites". | Low | This is ordinary browsing. No clause names an approved browser list. |
| Several chat cards (several web views) open at once on one account | ToU: "Interfere with or disrupt our Services, including circumvent any rate limits or restrictions". SIWC (not binding, but shows intent): "Creating multiple accounts, splitting usage, rotating accounts, or otherwise bypassing usage limits." | Low | It is the same as several browser tabs. The person sends each message, and plan limits still apply. It would only become a problem if cards were used to send in parallel automatically. |
| Bridge attaches the open PDF and page images, and adds quote chips, in an isolated content world | ToU: "Modify, copy, lease, sell or distribute any of our Services." | Low–medium | Folio changes the page as it is shown locally (inserted chips, a `<style>` element). It does not copy or redistribute OpenAI's code or service. "Modify … any of our Services" is broad and has not been tested against client-side changes. Browser extensions make the same kind of changes to chatgpt.com, but I found no OpenAI statement either way. |
| On Enter/Send, inserts CriticMarkup quotes and clicks Send for the person (never sends on its own) | ToU: "Automatically or programmatically extract data or Output." Usage Policies (Nov 20, 2026): "automation of high-stakes actions in sensitive areas without human review." | Low | The person starts every send, and the content is their own input. Nothing is extracted. Keep the "never sends on its own" rule absolute. A send that fires without a keypress or click (queued prompts, retries, batch "ask every page") would move this to medium or high. |
| Reads the DOM to render quotes in sent messages as chips, check whether a file is already in the conversation, and scroll to a message | ToU: "Automatically or programmatically extract data or Output (defined below)." Output means the model's responses. | Low–medium | The bridge reads the person's own user-message bubbles and attachment names, not model Output. It stores nothing and sends nothing off the page. The literal wording ("extract data") is broad enough that reading any page data with code could be argued. Keep reads limited to user messages and never read, save or export assistant responses. |
| Fetches `/api/auth/session` once after an import, to check the session | ToU: "Automatically or programmatically extract data". | Low | It is one same-origin request, with the person's own cookies, that the site's own JavaScript also makes. Nothing is stored beyond a yes/no. Don't call other `/api` or `/backend-api` endpoints directly; that is where "programmatic" access starts to look like an unofficial API client. |
| Copies chatgpt.com / openai.com session cookies from Chrome, Arc, Brave, Edge, ChatGPT Atlas and other browsers (consent dialog plus a keychain prompt) | ToU "Registration": "You may not share your account credentials or make your account available to anyone else". SIWC §1: "Do not ask users for their ChatGPT passwords or session cookies." SIWC §1: tokens only "through OpenAI's supported sign-in flow". | **Medium–high** | The person moves their own session between apps on their own Mac, so nothing is shared with anyone else, and SIWC does not formally apply. But OpenAI has written down, for third-party apps, that asking for session cookies is not allowed. Lifting `__Secure-next-auth.session-token` also skips OpenAI's sign-in flow and its device or risk checks, which could be read as "bypass any protective measures". Decrypting Chromium "Safe Storage" keys is the same technique cookie-stealing malware uses, so it invites antivirus flags and bad press. Reading ChatGPT Atlas's cookie store (OpenAI's own browser) sharpens all of this. |
| User agent set to `… Version/26.0 Safari/605.1.15` (Safari-like) | ToU: "bypass any protective measures or safety mitigations". | Low–medium | WKWebView is WebKit, so the string is mostly accurate about the engine. If chatgpt.com, or a sign-in provider, treats embedded views differently and the Safari token gets around that, it could be read as a bypass. |
| Google, Apple and Microsoft sign-in popups open inside Folio's web view, and the bridge script is also injected into those pages | Google OAuth 2.0 Policies: "A developer must not direct a Google OAuth 2.0 authorization request to an embedded user-agent under the developer's control." Embedded user-agents include libraries "that allow a developer to insert arbitrary scripts … or access session cookies." | Medium (Google's policy, not OpenAI's) | OpenAI, not Folio, sends the OAuth request, so the clause is aimed at OpenAI. Still, Folio is exactly the kind of embedded agent it describes. The bridge (`chatgpt-bridge.js`, added with `forMainFrameOnly: true` and no host check) runs a MutationObserver and adds a `<style>` element on any main-frame page, including `accounts.google.com` popups, because popups reuse the configuration. Google can block this at any time, and injecting scripts into Google's sign-in page is not a good look. |
| Uploading PDFs and page images on the person's behalf | Service Terms §6: "You may not use Visual Capabilities to assist in identifying a person nor to solicit or infer private or sensitive information about a person." ToU: "You represent and warrant that you have all rights … needed to provide Input". | Low | This responsibility belongs to the person, not Folio. Folio doesn't steer uploads toward anything restricted. |
| Model-access intermediaries (new rule, effective Nov 20, 2026) | Usage Policies: "If you operate a model-access intermediary platform or other service that enables third parties to directly access OpenAI models, you must obtain our prior review and approval. This requirement does not apply solely because an application integrates OpenAI models to power its features". | Low | Folio gives no third party access. Each person uses their own account in their own window. It would only apply if Folio ever routed requests through your server, pooled accounts or offered ChatGPT access to people without accounts. |
| Free distribution outside the App Store | ToU: "Modify, copy, lease, sell or distribute any of our Services." | Low | Folio ships none of OpenAI's code or content. It loads chatgpt.com live. Don't bundle or cache OpenAI assets (logos, scripts, fonts) in the app. |

## 3. Branding

### What OpenAI's guidelines say

From the [Brand guidelines](https://openai.com/brand/):

- **Ownership.** "The 'OpenAI' name, the OpenAI logo, the 'ChatGPT' and 'GPT' brands, and other OpenAI trademarks, are property of OpenAI."
- **App identity.** In the API Developers section: "you may truthfully identify the OpenAI technology you use. However, everything about your app, product or company (including name, logo, description, slogan, tagline and screenshots) should be your own and should be free of OpenAI's brands … You should not use the OpenAI logo or brand in any way that would imply sponsorship, affiliation or endorsement." Folio isn't an API developer, but this is the closest and strictest guidance, so plan around it.
- **Notifying users.** "If your product closely resembles an OpenAI product (such as ChatGPT), please make a clear indication to users that your product is independently developed and not affiliated, endorsed, or sponsored by OpenAI."
- **Names.** "We do not permit the use of OpenAI models or 'GPT' in product or app names". It also lists "Chat GPT, ChatGPT4, GPTChat" as misuses of the name.
- **Partnership language.** Non-partners must not say "collaborated with," "worked with," or "partnered with" OpenAI.
- **Logos.** Use the logo only "when it directly relates to OpenAI services". Don't "Use the logo without permission", "Use the logo more prominently than your own", or "Incorporate the logo into your own branding … or design a similar logo." Usage terms add "Do not feature our Marks more prominently than your own company's name or marks."
- **Terms of Use.** "You may only use our name and logo in accordance with our Brand Guidelines."

### Folio's current uses

| Where | Current use | Verdict |
|---|---|---|
| App name | "Folio" | Fine. Keep "ChatGPT" and "GPT" out of the name, bundle name and GitHub repo name (`alexmodrono/folio` is fine). |
| App icon | Folio's own icon | Fine, as long as it does not use or resemble the Blossom or wordmark, and has no chat-bubble-plus-knot motif. Check the final icon for this. |
| Context menu "Ask ChatGPT", "Ask ChatGPT About Page N" (`ReaderViewController.swift`) | Describes what the action does | Fine. It is nominative use: it names the service the text goes to, in plain text, with no logo. |
| Main menu "Chat" › "Ask About Selection" and others | No mark | Fine. It is the safest pattern. |
| Chat card title "ChatGPT", or the conversation title (`ChatCardViewController.swift`) | Labels a panel that literally shows chatgpt.com | Fine. It is accurate and is effectively the page title. |
| Settings section "ChatGPT", "Sign Out of ChatGPT…" | Names the account | Fine. |
| Import sheet: "Folio can copy your ChatGPT sign-in from a browser." | Names the account | The wording is fine. The feature is the problem (see §2). |
| `NSMicrophoneUsageDescription`: "ChatGPT voice input uses the microphone." | Explains a permission prompt | Fine. |
| About panel (`NSHumanReadableCopyright` is empty) | No disclaimer | **Add one** (see §4). |
| Website: "Works with your own ChatGPT account. Not affiliated with OpenAI." | Disclaimer | Good start. Make it complete and put it where people see it (see below). |
| Screenshots | Show chatgpt.com's UI inside Folio | Acceptable with care. The ChatGPT interface and logo will appear in them, and the brand page lists "screenshots" among things that should be "your own". Keep Folio's chrome and name dominant, crop or avoid the Blossom and large ChatGPT wordmarks, and don't use a screenshot whose most prominent element is ChatGPT. Add the disclaimer next to the screenshots or in the page footer. |

### Recommended wording

- **Tagline or headline:** describe Folio without the mark, for example "A fast PDF reader with a chat panel." Mention ChatGPT in the next line as a compatibility statement: "Works with your own ChatGPT account."
- **Avoid:** "ChatGPT for PDFs", "PDF ChatGPT", "Folio GPT", "GPT-powered", "Powered by ChatGPT" as a badge, "built with OpenAI", "official", "partnered with", and any OpenAI or ChatGPT logo on the site, icon or DMG background. "for ChatGPT" (as in "a PDF reader for ChatGPT") is nominative and usually acceptable in body copy. Keep it out of the title and tagline, though, because OpenAI's guidance wants those "free of OpenAI's brands".
- **Full disclaimer** for the website footer, the GitHub README and the About panel:

  > Folio is an independent app. It is not affiliated with, endorsed by, or sponsored by OpenAI. ChatGPT and OpenAI are trademarks of OpenAI. Your use of ChatGPT in Folio is subject to OpenAI's Terms of Use.

- **Short in-app version** (About panel credits or `NSHumanReadableCopyright`):

  > Not affiliated with OpenAI. ChatGPT is a trademark of OpenAI.

## 4. Recommended changes, in order of importance

1. **Remove the browser cookie import, or at least ChatGPT Atlas and the automatic offer.** This is the only behaviour that directly contradicts something OpenAI has written for third-party apps ("Do not ask users for their ChatGPT passwords or session cookies"). It is also the feature most likely to get Folio flagged by security tools. Ordinary sign-in in the panel already works. If you keep it anyway:
   - make it a non-default action, never shown before the sign-in page
   - drop ChatGPT Atlas from `BrowserSessions.swift`
   - copy only the session-token cookie, which is what the code does now; keep it that way
   - say in the sheet that this skips OpenAI's normal sign-in and that the person can sign in directly instead.
2. **Inject the bridge only on chatgpt.com.** Add a host check at the top of `chatgpt-bridge.js` (for example, return early unless `location.hostname` is `chatgpt.com`), and in the icon script as well. Folio would then no longer run scripts on `accounts.google.com`, `appleid.apple.com`, Microsoft or `auth.openai.com` pages. It is a small change that removes the clearest "embedded agent inserting scripts into OAuth pages" problem.
3. **Add the non-affiliation disclaimer** in three places:
   - the About panel (set `NSHumanReadableCopyright` in `project.yml`, or add credits)
   - the website footer and the GitHub README
   - next to the download button or screenshots on the website.

   Use the wording in §3.
4. **Write down the "person always sends" rule and keep it.** Folio never presses Send without a direct keypress or click by the person on that message. That rules out queued or batch prompts, auto-retry, scheduled asks, and "ask about every page". Add it to `CONTRIBUTING.md` so future changes don't break it, because it is what keeps Folio out of "programmatically" territory.
5. **Keep DOM reads limited to the person's own messages and composer.** Never read, save, index, export or sync assistant responses, conversation lists or history, and don't call `/backend-api` endpoints directly. The single `/api/auth/session` check is fine. Don't add more API calls.
6. **Tell people where the risk sits**, once and briefly, on the first-run chat panel or in the import sheet: "ChatGPT runs in this panel under your own account and OpenAI's terms." Don't go further and promise it is "allowed" or "safe" for their account.
7. **Fix the website copy** as in §3: a Folio-first headline, "Works with your own ChatGPT account" as a secondary line, no OpenAI logos, and no "official" or "partner" wording.
8. **Check the app icon and DMG art** against the Blossom: no hexagonal knot, no green or black circle-knot echo.
9. **Reconsider the Safari user-agent token.** Test whether chatgpt.com and sign-in work with WebKit's default user agent plus an honest `Folio/<version>` product token. If they do, prefer that, because it is harder to call deceptive. If sign-in only works with the Safari token, note the reason in a code comment and treat it as a known risk.
10. **Watch for SIWC.** If Sign in with ChatGPT ever becomes available to small developers in a form that fits Folio, it is the sanctioned route. It would change the design to API-style use under the SIWC Terms, which have their own no-charge, local-token and branding rules, and Folio would no longer need to automate chatgpt.com.

## 5. Open questions for a lawyer or for OpenAI

1. Does "Modify, copy, lease, sell or distribute any of our Services" cover client-side rendering changes in a person's own browser (chips, styles, composer edits)? Does "automatically or programmatically extract data" cover reading the person's own messages from the DOM to render them? Only OpenAI can say how it reads its own terms. A written answer from `partnercomms@openai.com` (brand) or `legal@openai.com` would settle it.
2. Is a third-party desktop app that embeds chatgpt.com acceptable to OpenAI at all, given that the person signs in themselves and every send is manual? There is no published policy on this. If OpenAI says no, the honest response is to stop shipping the panel, not to work around it.
3. Is importing the person's own ChatGPT session cookie from their own browser, on their own Mac and with their consent, a breach of the ToU for the person (credential sharing or bypassing protective measures)? Does SIWC's "Do not ask users for … session cookies" reach non-SIWC apps by analogy? Separately, could reading other browsers' encrypted cookie stores raise issues under computer-misuse or anti-circumvention law in your distribution markets (for example the EU, where you likely reside, and the US)?
4. Trademark: is "Ask ChatGPT" as a menu label, and "ChatGPT" as a panel title, nominative fair use in the US and permitted descriptive use under EU trademark law (Article 14 of the EU Trade Mark Regulation, "referring to … goods or services as those of the proprietor")? I believe yes, but a trademark lawyer should confirm. They should also confirm whether screenshots of ChatGPT's UI on the website need permission.
5. Google OAuth: does Folio's embedded web view (with the Safari user-agent token) put Folio, or OpenAI, in breach of Google's embedded user-agent rule? Should Google, Apple and Microsoft sign-in be pushed to the system browser, which would mean a different sign-in flow from OpenAI's?
6. Liability: if a person's account is suspended for using Folio, does Folio carry any exposure (for example, through the free-distribution licence or the lack of a disclaimer of fitness)? Folio's own licence or EULA should disclaim it either way.
7. The Usage Policies change effective November 20, 2026 (model-access intermediaries): please confirm that a local app with no server, where each person uses their own account, is outside "enables third parties to directly access OpenAI models."
