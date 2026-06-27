# AvareX landing page (for Google Ads)

A single-page, dependency-free landing page used as the **Final URL** for the Google Ads
campaign (see `../store/google-ads-campaign.md`). It routes visitors to the right app store
and fires a Google Ads **"Download"** conversion when a store button is clicked.

## Files
- `index.html` — the whole page (inline CSS/JS, no build step)
- `img/` — optimized screenshots

## 1. Wire up conversion tracking (required)
In Google Ads: **Tools → Conversions → New → Website → "Download"** (count: One, category: Submit lead form / Download).
Open the tag setup and copy two values, then edit `index.html`:
- Replace **`AW-CONVERSION_ID`** (appears 3×) with your conversion ID, e.g. `AW-123456789`.
- Replace **`CONVERSION_LABEL`** (1×, in `send_to`) with the conversion label.

That's it — every store-button click now reports a conversion and still opens the store.

## 2. Deploy (pick one)

**GitHub Pages (free, fastest):**
```bash
# from repo root, on a clean branch
git subtree push --prefix landing origin gh-pages
# or: copy landing/ into a separate repo and enable Pages on it
```
Then set Pages source to the `gh-pages` branch. URL will be `https://<user>.github.io/<repo>/`.

**Any static host** (Netlify / Cloudflare Pages / Vercel): point it at the `landing/` folder, no build command.

## 3. Use it in Google Ads
- Set each ad's **Final URL** to your deployed page **with UTM tags**, e.g.:
  `https://your-domain/?utm_source=google&utm_medium=cpc&utm_campaign=avarex_efb&utm_content=competitor`
- The page automatically appends that query string onto the outbound store links, so the
  source flows through to the store / Play Console.

## 4. Preview locally
```bash
cd landing && python3 -m http.server 8000
# open http://localhost:8000
```
