# Privacy

Folio has no accounts, no servers, no analytics, and no tracking. Everything Folio stores stays on your Mac. This page lists each case where something leaves your Mac, and the one case where Folio reads data from another app.

## The chat panel

The chat panel is chatgpt.com, signed in with your own ChatGPT account. What you type, attach, and send there goes to OpenAI and is covered by [OpenAI's privacy policy](https://openai.com/policies/privacy-policy/) and terms, the same as using chatgpt.com in a browser.

Opening a PDF doesn't upload it. It's uploaded only when you choose **Attach**, ask about a selection or page (which you can turn off), or turn on auto-attach. chatgpt.com uploads a file as soon as it's in the message box, even before you send. Folio never sends a message itself.

## Importing your sign-in

If you choose to reuse a browser's ChatGPT sign-in, Folio reads only the chatgpt.com and OpenAI sign-in cookies from the browser you pick, on your Mac. macOS asks you first: for your password to use the browser's keychain item, or for Full Disk Access in Safari's case. The cookies are copied only into Folio's own web view storage and aren't sent anywhere else.

## Question bubbles

Folio saves what you asked and on which page in `~/Library/Application Support/Folio/questions.json`, so it can draw bubbles later. Folio never modifies your PDFs.

## Update check

Once a day, Folio downloads a small file from its latest GitHub release that describes the newest version. The request carries the app's name and version and nothing else that identifies you beyond what any web request does, such as your IP address. Updates are downloaded from GitHub only when you choose to install one, and Folio checks their signature before installing. Turn the check off in **Settings › Updates**.

## Reporting a problem

**Help › Report a Problem…** opens a prefilled GitHub issue in your browser with the app version, the macOS version, and recent lines from Folio's log. Nothing is sent until you review the issue and submit it yourself.

## This website

This site bundles its fonts and runs search locally. It has no analytics. Theme, sound, and sidebar preferences are saved in your browser. Download and source links go to GitHub.
