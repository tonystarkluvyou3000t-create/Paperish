# Phase 08 — Implement orders and physical cargo
Read rules and 07 handoff. Extend the existing single delivery into a reliable receipt -> cargo -> customer system.

## Result
Every pizza package belongs to an order and exists at exactly one location. Pip must load the van, retrieve the right boxes and hand them to the correct customer. A full delivery is satisfying without repetitive inventory micromanagement.

## Milestone A — Order/cargo records
Define stable order/package IDs, destination/customer IDs, quantity, preparation/collection/delivery status, deadline, quality and settlement. Cargo locations: counter, Pip, van slot, customer, discarded. The order service owns lifecycle; cargo owns package location. Commit cross-service transitions atomically or roll back on rejection. Use explicit transitions, not a bag of booleans.

Support up to three queued jobs with configurable van capacity, while default/tutorial starts with one. A ticket cannot be accepted if capacity or a feasible route estimate rules it out. Before route service exists, use a conservative measured estimate and mark the later integration point.

## Milestone B — Physical load/unload
Add a rear/side cargo-door interaction distinct from driver entry. Show empty/occupied slots and readable order labels. One purposeful action loads the held ticket bundle; another retrieves the selected ticket bundle. The visual pizza stack reflects the authoritative location. Getting into the driver's seat cannot duplicate boxes or silently count as loading. A clear HUD ticket list shows where each bundle is.

Allow a short on-foot delivery without using the van where sensible; do not force driving for a neighboring house. Make quantity/carry capacity explicit. Avoid individual-box clicks for every routine order.

## Milestone C — Customer receiving and settlement
At the correct door, ring/knock and show a brief customer appearance or threshold conversation. Validate current customer, order ID, required quantity, cargo ownership and alive deadline. Wrong address/empty hands -> informative dialogue, no payout. Correct handoff -> animation, remove cargo once, itemized base pay/tip/quality adjustment, customer response, settlement event.

Separate order failure from shift failure. Timeout/cancel clears or reclassifies its boxes visibly, never leaves stale deliverable cargo. Document expiry policy and provide shop disposal/replacement without infinite free rewards. Delivery and expiry on the same frame resolve once through an explicit order transaction.

## Acceptance
One complete staff pickup -> van load -> drive -> safe exit -> unload -> customer dialogue -> payment works without teleport. Test wrong address/order, full van, duplicate E, expiration while carrying/loaded, restart and batch delivery in a different order. Assert total package counts/locations after each step and exactly one settlement. Timer freezes for mandatory receiving dialogue. Run core suite and add cargo invariant tests.

Handoff: schemas, capacities, order state machine, payment formula and settlement events. Do not add upgrades or complex recipe assembly yet.
