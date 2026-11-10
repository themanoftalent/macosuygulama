# Contributing to macOS Uygulama

Thanks for taking the time to help. This repository holds the website at [macosuygulama.vercel.app](https://macosuygulama.vercel.app). Issues about a specific app belong in that app's own repository.

## Good first contributions

1. Typos, grammar and clearer wording on any page.
2. Turkish translation fixes under `dist/tr/`.
3. A new language. Copy `dist/tr/` to `dist/<code>/`, translate the text, and register the language in `dist/locale.js`.
4. Screenshots or GIFs for an app in `dist/assets/`. Keep images under 500 KB and use PNG, WebP or GIF.
5. Broken links and outdated version numbers.

## Workflow

1. Fork the repository and create a branch: `git checkout -b fix/short-description`.
2. Preview your change locally:

   ```bash
   python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
   ```

3. Check both http://127.0.0.1:4173/ and http://127.0.0.1:4173/tr/ at desktop and phone widths.
4. Commit with a short message in the imperative, such as `Fix Clipale download link`.
5. Open a pull request that says what changed and why. Add a screenshot for visual changes.

Vercel builds a preview for every pull request, so reviewers can see your change before it merges.

## Ground rules

1. Keep the site static. No trackers, analytics scripts or third-party cookies.
2. Describe apps accurately. Claims about speed or security need a source, such as a benchmark or the app's own documentation.
3. Keep credits for upstream open-source projects intact.
4. Be respectful in issues and reviews.

## License of contributions

By opening a pull request you agree that your contribution is published under the same license as this repository.
