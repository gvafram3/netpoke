# Boutique fan-out instrumentation (Step 6) — source-level finding

**Question this answers:** why does boutique never show an I/O-gap signal (Phase 1/3 RMSE, Table
N1 residual I/O), and why does NetPoke actively *regress* its RMSE at L2 (Table N2, 3.53% →
10.26%) instead of merely having no effect?

**Method:** rather than dynamic call-count instrumentation (originally planned as "Step 6"), this
traces the actual live code path of each app's causal target service, since the answer turns out
to be visible directly in source: does the handler make any synchronous network call at all?

## What each target service's live code path actually does

| App | Target (`-x`) | Handler | Network calls in the live path |
|-----|---------------|---------|----------------------------------|
| Boutique | `cart` | `GetCart`/`AddItem`/`EmptyCart` ([`cart.go`](../../../../../slowpoke/app/internal/boutique/cart.go)) | **None.** Reads/writes an in-process `sync.Map` (`local_carts`). A Redis client and a `state.GetState` call exist in the file but are commented out / unused — dead code, not on the request path. |
| Hotel | `profile` | `GetProfiles` ([`profile.go`](../../../../../slowpoke/app/internal/hotel/profile.go)) | `slowpoke.GetBulkStateDefault` — a Dapr state-store round-trip (Redis-backed). |
| Movie | `moviereviews` | `ReadMovieReviews` ([`movie_reviews.go`](../../../../../slowpoke/app/internal/movie/movie_reviews.go)) | `slowpoke.GetState` (Dapr state store) **and** `slowpoke.Invoke(ctx, "reviewstorage", "ro_read_reviews", ...)` — an explicit HTTP call to another service. |
| Social | `hometimeline` | `ReadHomeTimeline` ([`home_timeline.go`](../../../../../slowpoke/app/internal/social/home_timeline.go)) | `slowpoke.GetState` (Dapr state store) **and** `slowpoke.Invoke(ctx, "poststorage", "ro_read_posts", ...)` — an explicit HTTP call to another service. |

`slowpoke.Invoke` (`app/pkg/invoke/invoke.go:198`) issues a real `http.NewRequest("POST", "http://localhost:<daprPort>/<method>", ...)` with a `dapr-app-id` header, routed by the Dapr sidecar to the named downstream service. `slowpoke.GetState`/`SetState` (`app/pkg/state/state.go`) go through the Dapr client's state API, backed by `common.RedisUrl` — also a real network round-trip. Both are genuine synchronous I/O that can be buffered mid-flight during a `SIGSTOP` pause. Boutique's cart handler calls neither.

## Conclusion

Boutique's cart target isn't "less I/O-bound than the others" — in its actual, live request-handling code, it performs **zero** synchronous network I/O. There is no downstream call, and no state-store round-trip, for kernel buffering to intercept during a pause window. That is not a hypothesis; it's directly readable from the handler functions. This explains, with a specific mechanism rather than an unexplained anomaly:

- Why boutique never showed an I/O-gap RMSE signal in Phase 1/3 (`TABLE_IO_GAP_MATRIX.md`) — there was never a real gap to inject into.
- Why Table N1's residual-I/O measurement was flat for boutique at both L0 and L2 — there's nothing for NetPoke's egress hold to intercept.
- Why Table N2 shows boutique's RMSE getting *worse* with NetPoke on, not just unaffected: the egress hold (netlink toggling, `tc` state changes on every `SIGSTOP`/`SIGCONT`) still has a real cost. With no residual I/O to suppress, that cost has nothing to offset it, so it shows up as pure added timing noise in the prediction.

This is a legitimate, source-grounded limitation to report — a documented case where the mitigation's overhead outweighs its benefit for a specific class of target service (one with no synchronous downstream I/O at all), not a flaw in the underlying mechanism.

## What would strengthen this further (not done here)

- Confirm no *other* boutique service on the injected L2 path (`productcatalog`, `currency`) makes
  real network calls either, the same way — same source-reading method, just not yet done for
  those two.
- A quick dynamic check: `strace -f -e trace=network -p <cart_pid>` during a run, to confirm zero
  outbound socket activity from the cart process specifically (would corroborate the static
  reading with a live measurement, cheap to run whenever cluster time is available next).
