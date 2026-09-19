---
name: network-triage
description: Diagnose a dropped link, DNS failure, or unreachable host on the hub.
surfaces: text, voice
---

Work the layers from the bottom up. Each step rules out everything below it, so
do not skip ahead — a DNS theory is worthless while the link is down.

First, the link. Ask whether the machine has an address at all. No address means
DHCP or the interface, not the network.

Second, the route. Ask whether the default gateway answers. A gateway that
answers while the wider internet does not puts the fault upstream of the hub,
which is not something the Pilot can fix from here.

Third, name resolution. A host that answers by address but not by name is DNS.
On this hub that usually means the resolver configured by NixOS is unreachable,
not that the record is wrong.

Fourth, the service. If names resolve and the route is good, the fault is the
service itself. Ollama not answering on port eleven four three four is the
common case, and it is a service problem, not a network one.

Report the layer that failed and the single next action. Do not list every step
you ruled out.
